WITH recent_users AS (
  SELECT u.Id, u.Reputation, u.CreationDate
  FROM Users u
  WHERE u.CreationDate >= (SELECT MAX(CreationDate) - INTERVAL '365 days' FROM Users)
),
questions AS (
  SELECT p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.Tags, p.Title, p.AcceptedAnswerId
  FROM Posts p
  WHERE p.PostTypeId = 1
),
answers AS (
  SELECT a.Id, a.ParentId, a.OwnerUserId, a.CreationDate, a.Score
  FROM Posts a
  WHERE a.PostTypeId = 2
),
tag_expansion AS (
  SELECT q.Id AS QuestionId, unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS TagName
  FROM questions q
  WHERE q.Tags IS NOT NULL AND q.Tags <> ''
),
tag_popularity AS (
  SELECT te.TagName, COUNT(*) AS QuestionCount
  FROM tag_expansion te
  GROUP BY te.TagName
  HAVING COUNT(*) > 10
),
q_activity AS (
  SELECT
    q.Id AS QuestionId,
    q.OwnerUserId,
    q.CreationDate AS QuestionCreation,
    q.Score AS QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT a.Id) FILTER (WHERE a.Score > 0) AS PositiveAnswers,
    COUNT(DISTINCT a.Id) FILTER (WHERE a.Score <= 0) AS NonPositiveAnswers,
    MAX(a.Score) AS MaxAnswerScore,
    MIN(a.Score) AS MinAnswerScore,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 5) AS Favorites,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10,11,12,13,14,15,19,20,35) THEN ph.Id END) AS ModEvents
  FROM questions q
  LEFT JOIN answers a ON a.ParentId = q.Id
  LEFT JOIN Comments c ON c.PostId = q.Id
  LEFT JOIN Votes v ON v.PostId = q.Id
  LEFT JOIN PostHistory ph ON ph.PostId = q.Id
  GROUP BY q.Id, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount
),
first_answer_latency AS (
  SELECT
    q.Id AS QuestionId,
    CAST(EXTRACT(epoch FROM (MIN(a.CreationDate) - q.CreationDate)) AS BIGINT) AS SecondsToFirstAnswer
  FROM questions q
  LEFT JOIN answers a ON a.ParentId = q.Id
  GROUP BY q.Id, q.CreationDate
),
accepts AS (
  SELECT q.Id AS QuestionId, CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAccepted
  FROM Posts q
  WHERE q.PostTypeId = 1
),
hotness_candidates AS (
  SELECT
    qa.QuestionId,
    qa.QuestionScore,
    qa.ViewCount,
    qa.AnswerCount,
    fa.SecondsToFirstAnswer,
    qa.UpVotes,
    qa.DownVotes,
    qa.Favorites,
    qa.CommentCount,
    qa.ModEvents,
    COALESCE(AVG(a.Score) FILTER (WHERE a.ParentId = qa.QuestionId), 0) AS AvgAnswerScore,
    COALESCE(SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END) FILTER (WHERE a.ParentId = qa.QuestionId), 0) AS PosAnswerCnt
  FROM q_activity qa
  LEFT JOIN answers a ON a.ParentId = qa.QuestionId
  LEFT JOIN first_answer_latency fa ON fa.QuestionId = qa.QuestionId
  GROUP BY qa.QuestionId, qa.QuestionScore, qa.ViewCount, qa.AnswerCount, fa.SecondsToFirstAnswer, qa.UpVotes, qa.DownVotes, qa.Favorites, qa.CommentCount, qa.ModEvents
),
user_stats AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAuthored,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersAuthored,
    SUM(p.Score) AS TotalPostScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
    COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.Reputation
),
dup_graph AS (
  SELECT pl.PostId AS DuplicateId, pl.RelatedPostId AS CanonicalId
  FROM PostLinks pl
  WHERE pl.LinkTypeId = 3
),
dup_clusters AS (
  SELECT
    g.CanonicalId,
    COUNT(DISTINCT g.DuplicateId) AS DuplicateCount,
    COUNT(DISTINCT g.CanonicalId) AS CanonicalPresence
  FROM dup_graph g
  GROUP BY g.CanonicalId
),
tagged_questions AS (
  SELECT te.QuestionId, te.TagName
  FROM tag_expansion te
  INNER JOIN tag_popularity tp ON tp.TagName = te.TagName
),
tag_metrics AS (
  SELECT
    tq.TagName,
    COUNT(*) AS QuestionsInTag,
    CAST(AVG(q.Score) AS NUMERIC(18,6)) AS AvgQScore,
    CAST(AVG(q.ViewCount) AS NUMERIC(18,6)) AS AvgViews,
    CAST(AVG(q.AnswerCount) AS NUMERIC(18,6)) AS AvgAnswers
  FROM tagged_questions tq
  JOIN questions q ON q.Id = tq.QuestionId
  GROUP BY tq.TagName
),
recent_q_window AS (
  SELECT q.Id, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount
  FROM questions q
  WHERE q.CreationDate >= (SELECT MAX(CreationDate) - INTERVAL '90 days' FROM Posts)
),
rolling_user_q AS (
  SELECT
    rq.OwnerUserId,
    rq.Id AS QuestionId,
    rq.CreationDate,
    SUM(1) OVER (PARTITION BY rq.OwnerUserId ORDER BY rq.CreationDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS QsInLast7
  FROM recent_q_window rq
),
final AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate,
    u.DisplayName AS OwnerName,
    us.Reputation AS OwnerReputation,
    us.QuestionsAuthored,
    us.AnswersAuthored,
    us.TotalPostScore,
    us.TotalAnswerScore,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    hc.QuestionScore,
    hc.ViewCount,
    hc.AnswerCount,
    hc.SecondsToFirstAnswer,
    hc.UpVotes,
    hc.DownVotes,
    hc.Favorites,
    hc.CommentCount,
    hc.ModEvents,
    hc.AvgAnswerScore,
    hc.PosAnswerCnt,
    COALESCE(ac.HasAccepted, 0) AS HasAccepted,
    COALESCE(dc.DuplicateCount, 0) AS DuplicateGroupSize,
    COALESCE(tm.AvgQScore, 0) AS TagAvgQScore,
    COALESCE(tm.AvgViews, 0) AS TagAvgViews,
    COALESCE(tm.AvgAnswers, 0) AS TagAvgAnswers,
    COALESCE(rw.QsInLast7, 0) AS RecentQsByOwner,
    COUNT(DISTINCT tq.TagName) AS TagCount
  FROM questions q
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  LEFT JOIN user_stats us ON us.UserId = q.OwnerUserId
  LEFT JOIN hotness_candidates hc ON hc.QuestionId = q.Id
  LEFT JOIN accepts ac ON ac.QuestionId = q.Id
  LEFT JOIN dup_clusters dc ON dc.CanonicalId = q.Id
  LEFT JOIN tagged_questions tq ON tq.QuestionId = q.Id
  LEFT JOIN tag_metrics tm ON tm.TagName = (
    SELECT tq2.TagName
    FROM tagged_questions tq2
    JOIN tag_metrics tm2 ON tm2.TagName = tq2.TagName
    WHERE tq2.QuestionId = q.Id
    ORDER BY tm2.AvgViews DESC NULLS LAST
    LIMIT 1
  )
  LEFT JOIN rolling_user_q rw ON rw.QuestionId = q.Id
  GROUP BY
    q.Id, q.Title, q.CreationDate, u.DisplayName,
    us.Reputation, us.QuestionsAuthored, us.AnswersAuthored, us.TotalPostScore, us.TotalAnswerScore, us.GoldBadges, us.SilverBadges, us.BronzeBadges,
    hc.QuestionScore, hc.ViewCount, hc.AnswerCount, hc.SecondsToFirstAnswer, hc.UpVotes, hc.DownVotes, hc.Favorites, hc.CommentCount, hc.ModEvents, hc.AvgAnswerScore, hc.PosAnswerCnt,
    ac.HasAccepted, dc.DuplicateCount, tm.AvgQScore, tm.AvgViews, tm.AvgAnswers, rw.QsInLast7
)
SELECT
  f.*,
  CASE
    WHEN f.SecondsToFirstAnswer IS NULL THEN 0
    WHEN f.SecondsToFirstAnswer < 3600 THEN 5
    WHEN f.SecondsToFirstAnswer < 6*3600 THEN 4
    WHEN f.SecondsToFirstAnswer < 24*3600 THEN 3
    WHEN f.SecondsToFirstAnswer < 72*3600 THEN 2
    ELSE 1
  END AS FirstAnswerSpeedScore,
  (COALESCE(f.QuestionScore,0) * 2 + COALESCE(f.UpVotes,0) - COALESCE(f.DownVotes,0) + COALESCE(f.Favorites,0)) AS EngagementScore,
  CAST((COALESCE(f.ViewCount,0) / GREATEST(1, f.TagAvgViews)) AS NUMERIC(18,6)) AS ViewRelToTag,
  CAST((COALESCE(f.AnswerCount,0) - COALESCE(f.TagAvgAnswers,0)) AS NUMERIC(18,6)) AS AnswerDeltaFromTag,
  CAST((COALESCE(f.AvgAnswerScore,0) - COALESCE(f.TagAvgQScore,0)) AS NUMERIC(18,6)) AS AnswerQualityVsTag
FROM final f
WHERE f.CreationDate >= (SELECT MAX(CreationDate) - INTERVAL '365 days' FROM Posts)
ORDER BY EngagementScore DESC, FirstAnswerSpeedScore DESC, f.ViewCount DESC
LIMIT 500;