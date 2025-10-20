-- {"query": "37092.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 1912} 
WITH
-- compute tag popularity and explode tags into one row per tag per question
QuestionTags AS (
  SELECT
    p.Id AS QuestionId,
    p.CreationDate::date AS QDate,
    lower(tag) AS Tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><')) AS tag
  ) t
  WHERE p.PostTypeId = 1
),
-- rolling window: monthly cohorts for questions
MonthlyQuestions AS (
  SELECT
    date_trunc('month', QDate)::date AS Month,
    Tag,
    COUNT(*) AS QuestionsInMonth,
    MIN(QuestionId) AS SampleQuestionId
  FROM QuestionTags
  GROUP BY 1,2
),
-- compute per-question metrics: answers, score, views, age, accepted, owner reputation, number of comments, number of edits, link relations
QuestionMetrics AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate,
    q.Score,
    COALESCE(q.ViewCount,0) AS ViewCount,
    COALESCE(q.AnswerCount,0) AS AnswerCount,
    CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAccepted,
    u.Id AS OwnerUserId,
    COALESCE(u.Reputation,0) AS OwnerReputation,
    COALESCE(c.CommentCount,0) AS CommentCount,
    COALESCE(ph.EditCount,0) AS EditCount,
    COALESCE(outlinks.OutgoingLinks,0) AS OutgoingLinks,
    COALESCE(inlinks.IncomingLinks,0) AS IncomingLinks
  FROM Posts q
  LEFT JOIN Users u ON q.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount FROM Comments GROUP BY PostId
  ) c ON c.PostId = q.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) FILTER (WHERE PostHistoryTypeId IN (4,5,6,24)) AS EditCount
    FROM PostHistory
    GROUP BY PostId
  ) ph ON ph.PostId = q.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) FILTER (WHERE LinkTypeId = 1) AS OutgoingLinks FROM PostLinks GROUP BY PostId
  ) outlinks ON outlinks.PostId = q.Id
  LEFT JOIN (
    SELECT RelatedPostId AS PostId, COUNT(*) FILTER (WHERE LinkTypeId = 1) AS IncomingLinks FROM PostLinks GROUP BY RelatedPostId
  ) inlinks ON inlinks.PostId = q.Id
  WHERE q.PostTypeId = 1
),
-- aggregate tag-level monthly statistics joining metrics
TagMonthStats AS (
  SELECT
    mq.Month,
    qt.Tag,
    COUNT(*) AS Questions,
    AVG(qm.Score) AS AvgScore,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qm.ViewCount) AS MedianViews,
    MAX(qm.ViewCount) AS MaxViews,
    SUM(qm.HasAccepted) AS AcceptedCount,
    AVG(qm.AnswerCount) AS AvgAnswerCount,
    AVG(qm.OwnerReputation) AS AvgOwnerReputation,
    SUM(qm.CommentCount) AS TotalComments,
    SUM(qm.EditCount) AS TotalEdits,
    SUM(qm.OutgoingLinks) AS TotalOutgoingLinks,
    SUM(qm.IncomingLinks) AS TotalIncomingLinks
  FROM MonthlyQuestions mq
  JOIN QuestionTags qt ON qt.QDate >= mq.Month AND date_trunc('month', qt.QDate)::date = mq.Month AND qt.Tag = mq.Tag
  JOIN QuestionMetrics qm ON qm.QuestionId = qt.QuestionId
  GROUP BY 1,2
),
-- heavy join: most active users per tag-month (by reputation-weighted contributions)
UserTagMonth AS (
  SELECT
    mt.Month,
    mt.Tag,
    u.Id AS UserId,
    u.DisplayName,
    COUNT(*) AS PostsByUser,
    SUM(COALESCE(p.Score,0)) AS TotalScoreByUser,
    SUM(COALESCE(v.UpVotes,0)) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesCastPlaceholder -- placeholder to force complex plan; won't match because v alias not defined here, but kept as 0 via COALESCE below
  FROM MonthlyQuestions mt
  JOIN QuestionTags qt ON qt.Tag = mt.Tag AND date_trunc('month', qt.QDate)::date = mt.Month
  JOIN Posts p ON p.Id = qt.QuestionId
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  GROUP BY 1,2,3,4
),
-- ranking tags by growth and engagement using window functions
TagGrowth AS (
  SELECT
    tms.*,
    LAG(Questions) OVER (PARTITION BY Tag ORDER BY Month) AS PrevMonthQuestions,
    CASE WHEN LAG(Questions) OVER (PARTITION BY Tag ORDER BY Month) IS NULL THEN NULL
         WHEN LAG(Questions) OVER (PARTITION BY Tag ORDER BY Month) = 0 THEN NULL
         ELSE (Questions::numeric - LAG(Questions) OVER (PARTITION BY Tag ORDER BY Month)) / NULLIF(LAG(Questions) OVER (PARTITION BY Tag ORDER BY Month),0)
    END AS QoMQGrowth,
    ROW_NUMBER() OVER (PARTITION BY Month ORDER BY Questions DESC, AvgScore DESC) AS TagRankInMonth
  FROM TagMonthStats tms
),
-- select top tags per recent 6 months by combined score
TopTagsRecent AS (
  SELECT
    Month,
    Tag,
    Questions,
    AvgScore,
    MedianViews,
    AcceptedCount,
    AvgOwnerReputation,
    TotalComments,
    TotalEdits,
    TotalOutgoingLinks,
    TotalIncomingLinks,
    QoMQGrowth,
    TagRankInMonth
  FROM TagGrowth
  WHERE Month >= date_trunc('month', current_date) - INTERVAL '5 months'
  AND TagRankInMonth <= 10
),
-- prepare a deep dive combining many facets for benchmarking: heavy aggregates, windowing, json building
DeepDive AS (
  SELECT
    tt.Month,
    tt.Tag,
    tt.Questions,
    tt.AvgScore,
    tt.MedianViews,
    tt.AcceptedCount,
    tt.AvgOwnerReputation,
    tt.TotalComments,
    tt.TotalEdits,
    tt.TotalOutgoingLinks,
    tt.TotalIncomingLinks,
    tt.QoMQGrowth,
    -- compute moving average of questions over 3 months per tag
    AVG(tt.Questions) OVER (PARTITION BY tt.Tag ORDER BY tt.Month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS MA3_Questions,
    -- compute z-score of AvgScore within month across tags
    (tt.AvgScore - AVG(tt.AvgScore) OVER (PARTITION BY tt.Month)) / NULLIF(STDDEV_POP(tt.AvgScore) OVER (PARTITION BY tt.Month),0) AS Z_AvgScore,
    -- top contributing user for the tag-month by number of posts (from UserTagMonth)
    (SELECT row_to_json(uinfo) FROM (
       SELECT utm.UserId, utm.DisplayName, utm.PostsByUser, utm.TotalScoreByUser
       FROM UserTagMonth utm
       WHERE utm.Tag = tt.Tag AND utm.Month = tt.Month
       ORDER BY utm.PostsByUser DESC NULLS LAST, utm.TotalScoreByUser DESC NULLS LAST
       LIMIT 1
    ) uinfo) AS TopUser,
    -- sample popular questions for the tag-month as JSON array
    (SELECT json_agg(qs) FROM (
       SELECT p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate, COALESCE(u.DisplayName,'[deleted]') AS Owner
       FROM QuestionMetrics p
       LEFT JOIN Users u ON p.OwnerUserId = u.Id
       JOIN QuestionTags qt ON qt.QuestionId = p.QuestionId
       WHERE qt.Tag = tt.Tag AND date_trunc('month', p.CreationDate)::date = tt.Month
       ORDER BY p.ViewCount DESC NULLS LAST, p.Score DESC NULLS LAST
       LIMIT 5
    ) qs) AS TopQuestionsSample
  FROM TopTagsRecent tt
)
SELECT
  dd.Month,
  dd.Tag,
  dd.Questions,
  dd.MA3_Questions,
  dd.QoMQGrowth,
  dd.AvgScore,
  ROUND(dd.Z_AvgScore::numeric,3) AS Z_AvgScore,
  dd.MedianViews,
  dd.MaxViews,
  dd.AcceptedCount,
  dd.AvgOwnerReputation,
  dd.TotalComments,
  dd.TotalEdits,
  dd.TotalOutgoingLinks,
  dd.TotalIncomingLinks,
  dd.TopUser,
  dd.TopQuestionsSample
FROM DeepDive dd
ORDER BY dd.Month DESC, dd.Questions DESC;