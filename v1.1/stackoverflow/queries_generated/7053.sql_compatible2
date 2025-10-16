WITH
RecentQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    COALESCE(p.ViewCount, 0) AS Views,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    COALESCE(p.FavoriteCount, 0) AS Favorites,
    regexp_split_to_table(substring(COALESCE(p.Tags, ''), 2, GREATEST(length(COALESCE(p.Tags, '')) - 2, 0)), E'\\><') AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years'
),
BestAnswer AS (
  SELECT
    a.ParentId AS QuestionId,
    a.Id AS AnswerId,
    a.OwnerUserId AS AnswerOwner,
    a.Score AS AnswerScore,
    a.CreationDate AS AnswerCreation,
    ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate DESC) AS rn
  FROM Posts a
  WHERE a.PostTypeId = 2
),
FilterBestAnswer AS (
  SELECT QuestionId, AnswerId, AnswerOwner, AnswerScore, AnswerCreation
  FROM BestAnswer
  WHERE rn = 1
),
PostVoteAgg AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites,
    SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotes,
    COUNT(*) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS VoteScore
  FROM Votes v
  GROUP BY v.PostId
),
LastEditor AS (
  SELECT p.Id AS PostId,
         ph.UserId AS LastEditorUserId,
         ph.CreationDate AS LastEditDate,
         ph.PostHistoryTypeId,
         ph.Comment
  FROM Posts p
  LEFT JOIN LATERAL (
    SELECT ph2.UserId, ph2.CreationDate, ph2.PostHistoryTypeId, ph2.Comment
    FROM PostHistory ph2
    WHERE ph2.PostId = p.Id AND ph2.UserId IS NOT NULL
    ORDER BY ph2.CreationDate DESC
    LIMIT 1
  ) ph ON true
),
TagPopularity AS (
  SELECT
    rq.Tag AS TagName,
    COUNT(DISTINCT rq.QuestionId) AS QuestionCount,
    SUM(rq.Views) AS TotalViews,
    AVG(CASE WHEN rq.Score IS NOT NULL THEN rq.Score END) AS AvgScore,
    MAX(rq.Views) AS MaxViews
  FROM RecentQuestions rq
  GROUP BY rq.Tag
),
UserMetrics AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COALESCE(u.Views, 0) AS ProfileViews,
    COALESCE(SUM(CASE WHEN p.PostTypeId IN (1, 2) THEN p.Score ELSE 0 END), 0) AS AggregatePostScore,
    COALESCE(SUM(COALESCE(vp.UpVotes, 0)), 0) AS ReceivedUpVotes,
    COALESCE(COUNT(b.Id), 0) AS BadgeCount,
    (
      (CAST(u.Reputation AS numeric) / NULLIF(GREATEST(1, u.Reputation), 0) * 0.01)
      + (COALESCE(SUM(CASE WHEN p.PostTypeId IN (1, 2) THEN p.Score ELSE 0 END), 0) * 0.6)
      + (COALESCE(SUM(COALESCE(vp.UpVotes, 0)), 0) * 0.3)
      + (COALESCE(COUNT(b.Id), 0) * 0.1)
    ) AS CompositeScore
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN PostVoteAgg vp ON vp.PostId = p.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views
),
TagTopContributors AS (
  SELECT
    tp.TagName,
    um.UserId,
    um.DisplayName,
    SUM(COALESCE(p.Score, 0)) AS ScoreForTag,
    COUNT(DISTINCT p.Id) AS PostsForTag,
    RANK() OVER (PARTITION BY tp.TagName ORDER BY SUM(COALESCE(p.Score, 0)) DESC, COUNT(DISTINCT p.Id) DESC) AS TagRank
  FROM RecentQuestions rq
  JOIN Posts p ON p.Id = rq.QuestionId
  JOIN UserMetrics um ON um.UserId = p.OwnerUserId
  JOIN TagPopularity tp ON tp.TagName = rq.Tag
  GROUP BY tp.TagName, um.UserId, um.DisplayName
),
QuestionEnriched AS (
  SELECT
    rq.QuestionId,
    rq.Title,
    rq.OwnerUserId,
    rq.CreationDate,
    rq.Score AS QScore,
    rq.Views,
    rq.AnswerCount,
    rq.Tag,
    fba.AnswerId,
    fba.AnswerOwner,
    fba.AnswerScore,
    pva.UpVotes AS QUpVotes,
    pva.DownVotes AS QDownVotes,
    pva.VoteScore AS QVoteScore,
    le.LastEditorUserId,
    le.LastEditDate,
    tp.QuestionCount AS TagQuestionCount,
    tp.TotalViews AS TagTotalViews,
    tp.AvgScore AS TagAvgScore
  FROM RecentQuestions rq
  LEFT JOIN FilterBestAnswer fba ON fba.QuestionId = rq.QuestionId
  LEFT JOIN PostVoteAgg pva ON pva.PostId = rq.QuestionId
  LEFT JOIN LastEditor le ON le.PostId = rq.QuestionId
  LEFT JOIN TagPopularity tp ON tp.TagName = rq.Tag
),
Ranked AS (
  SELECT
    qe.QuestionId,
    qe.Title,
    qe.OwnerUserId,
    qe.CreationDate,
    qe.QScore,
    qe.Views,
    qe.AnswerCount,
    qe.Tag,
    qe.AnswerId,
    qe.AnswerOwner,
    qe.AnswerScore,
    qe.QUpVotes,
    qe.QDownVotes,
    qe.QVoteScore,
    qe.LastEditorUserId,
    qe.LastEditDate,
    qe.TagQuestionCount,
    qe.TagTotalViews,
    qe.TagAvgScore,
    ROW_NUMBER() OVER (
      PARTITION BY qe.Tag
      ORDER BY (COALESCE(qe.QVoteScore, 0) * 0.7 + COALESCE(qe.Views, 0) * 0.0001 + COALESCE(qe.AnswerCount, 0) * 0.5 + COALESCE(qe.TagQuestionCount, 0) * 0.01) DESC,
               qe.CreationDate DESC
    ) AS TagRowNum,
    PERCENT_RANK() OVER (PARTITION BY qe.Tag ORDER BY qe.QScore DESC) AS ScorePercentile
  FROM QuestionEnriched qe
  WHERE qe.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
    AND ((qe.Views IS NOT NULL AND qe.Views > 50) OR qe.AnswerCount >= 1)
),
Anomalies AS (
  SELECT
    r.QuestionId,
    r.Title,
    r.OwnerUserId,
    r.CreationDate,
    r.QScore,
    r.Views,
    r.AnswerCount,
    r.Tag,
    r.AnswerId,
    r.AnswerOwner,
    r.AnswerScore,
    r.QUpVotes,
    r.QDownVotes,
    r.QVoteScore,
    r.LastEditorUserId,
    r.LastEditDate,
    r.TagQuestionCount,
    r.TagTotalViews,
    r.TagAvgScore,
    r.TagRowNum,
    r.ScorePercentile
  FROM Ranked r
  WHERE
    (
      r.Views > (
        SELECT COALESCE(AVG(q.Views), 0) + 3 * COALESCE(stddev_pop(q.Views), 0)
        FROM QuestionEnriched q
        WHERE q.Tag = r.Tag
      )
      AND r.QScore <= (
        SELECT COALESCE(percentile_cont(0.25) WITHIN GROUP (ORDER BY q.QScore), 0)
        FROM QuestionEnriched q
        WHERE q.Tag = r.Tag
      )
    )
    OR
    (
      r.Views < (
        SELECT COALESCE(AVG(q.Views), 0) - 2 * COALESCE(stddev_pop(q.Views), 0)
        FROM QuestionEnriched q
        WHERE q.Tag = r.Tag
      )
      AND r.QScore >= (
        SELECT COALESCE(percentile_cont(0.90) WITHIN GROUP (ORDER BY q.QScore), 0)
        FROM QuestionEnriched q
        WHERE q.Tag = r.Tag
      )
    )
)
SELECT
  a.QuestionId,
  COALESCE(a.Title, '(no title)') AS Title,
  COALESCE(u.DisplayName, 'Community') AS QuestionOwner,
  a.CreationDate,
  a.QScore,
  a.Views,
  a.AnswerCount,
  a.Tag,
  a.AnswerId,
  a.AnswerOwner,
  a.AnswerScore,
  a.QUpVotes,
  a.QDownVotes,
  a.QVoteScore,
  a.LastEditorUserId,
  a.LastEditDate,
  a.TagQuestionCount,
  a.TagTotalViews,
  a.TagAvgScore,
  a.TagRowNum,
  ROUND(CAST(a.ScorePercentile AS numeric), 4) AS ScorePercentile,
  COALESCE((
    SELECT string_agg((ttc.DisplayName || ' (' || ttc.ScoreForTag || '/' || ttc.PostsForTag || ')'), '; ' ORDER BY ttc.ScoreForTag DESC)
    FROM TagTopContributors ttc
    WHERE ttc.TagName = a.Tag AND ttc.TagRank <= 3
  ), '(no contributors)') AS TopContributors,
  (CASE
     WHEN (a.AnswerId IS NULL OR a.AnswerScore IS NULL) AND a.ScorePercentile < 0.25 THEN 'NeedsAttention'
     WHEN a.AnswerId IS NOT NULL AND a.AnswerScore >= GREATEST(5, COALESCE(a.QScore, 0) * 0.5) THEN 'WellAnswered'
     WHEN a.Views > GREATEST(1000, a.TagTotalViews * 0.1) THEN 'Popular'
     ELSE 'Normal'
   END) AS Status
FROM Anomalies a
LEFT JOIN Users u ON u.Id = a.OwnerUserId
WHERE a.Tag IS NOT NULL
ORDER BY a.Tag, a.TagRowNum, a.ScorePercentile DESC
LIMIT 500;