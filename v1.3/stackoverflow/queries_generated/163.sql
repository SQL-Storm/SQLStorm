-- {"query": "163.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2871} 
WITH
q AS (
  SELECT *
  FROM Posts
  WHERE PostTypeId = 1
),
a AS (
  SELECT *
  FROM Posts
  WHERE PostTypeId = 2
),
tag_exploded AS (
  SELECT q.Id AS QuestionId,
         unnest(string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><')) AS Tag
  FROM q
  WHERE q.Tags IS NOT NULL
),
user_scores AS (
  SELECT u.Id,
         u.DisplayName,
         u.Reputation,
         COUNT(DISTINCT q.Id) AS Questions,
         COUNT(DISTINCT a.Id) AS Answers,
         SUM(COALESCE(a.Score, 0)) AS AnswerScore
  FROM Users u
  LEFT JOIN q ON q.OwnerUserId = u.Id
  LEFT JOIN a ON a.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
tag_stats AS (
  SELECT te.Tag,
         COUNT(DISTINCT te.QuestionId) AS QCount,
         AVG(q.Score) FILTER (WHERE q.Score IS NOT NULL) AS AvgQScore,
         MAX(q.ViewCount) AS MaxViews
  FROM tag_exploded te
  LEFT JOIN q ON q.Id = te.QuestionId
  GROUP BY te.Tag
),
hot_questions AS (
  SELECT q.Id,
         q.Title,
         q.CreationDate,
         q.Score,
         q.ViewCount,
         rank() OVER (PARTITION BY date_trunc('month', q.CreationDate) ORDER BY q.Score DESC, q.ViewCount DESC) AS monthly_rank
  FROM q
),
recent_activity AS (
  SELECT p.Id,
         p.OwnerUserId,
         p.LastActivityDate,
         row_number() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
),
badge_summary AS (
  SELECT b.UserId,
         count(*) AS Badges,
         sum(case when b.Class = 1 then 1 else 0 end) AS Gold,
         sum(case when b.Class = 2 then 1 else 0 end) AS Silver,
         sum(case when b.Class = 3 then 1 else 0 end) AS Bronze
  FROM Badges b
  GROUP BY b.UserId
),
user_complex AS (
  SELECT u.Id,
         u.DisplayName,
         u.Reputation,
         COALESCE(us.Questions, 0) AS Questions,
         COALESCE(us.Answers, 0) AS Answers,
         COALESCE(us.AnswerScore, 0) AS AnswerScore,
         COALESCE(bs.Badges, 0) AS Badges,
         COALESCE(bs.Gold, 0) AS Gold,
         COALESCE(bs.Silver, 0) AS Silver,
         COALESCE(bs.Bronze, 0) AS Bronze,
         (SELECT count(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpVotesGiven,
         (SELECT count(*) FROM Comments c WHERE c.UserId = u.Id AND c.CreationDate > u.CreationDate) AS CommentsMade
  FROM Users u
  LEFT JOIN user_scores us ON us.Id = u.Id
  LEFT JOIN badge_summary bs ON bs.UserId = u.Id
),
combined_tags AS (
  SELECT ts.Tag,
         ts.QCount,
         ts.AvgQScore,
         ts.MaxViews,
         dense_rank() OVER (ORDER BY ts.QCount DESC, ts.AvgQScore DESC NULLS LAST) AS popularity_rank
  FROM tag_stats ts
),
top_lists AS (
  SELECT 'top_tag' AS kind, Tag::text AS key, QCount::text AS val, popularity_rank AS ord
  FROM combined_tags
  WHERE popularity_rank <= 25
  UNION ALL
  SELECT 'top_user' AS kind,
         uc.DisplayName::text AS key,
         (uc.Reputation || '|' || COALESCE(uc.Questions,0) || 'Q|' || COALESCE(uc.Answers,0) || 'A|' || COALESCE(uc.Badges,0) || 'B')::text AS val,
         row_number() OVER (ORDER BY uc.Reputation DESC NULLS LAST, uc.Answers DESC NULLS LAST) AS ord
  FROM user_complex uc
  ORDER BY ord
),
anomalies AS (
  SELECT p.Id,
         p.Title,
         p.OwnerUserId,
         p.Score,
         p.ViewCount,
         CASE
           WHEN p.Score IS NULL THEN 'SCORE_NULL'
           WHEN p.Score < 0 AND p.ViewCount > 10000 THEN 'NEG_HIGH_VIEWS'
           WHEN p.Score > 100 AND (p.ViewCount IS NULL OR p.ViewCount < 10) THEN 'HIGH_SCORE_LOW_VIEWS'
           WHEN p.ClosedDate IS NOT NULL AND p.Score > 50 THEN 'CLOSED_HIGH_SCORE'
           ELSE 'NORMAL'
         END AS anomaly
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
),
final_users AS (
  SELECT uc.Id AS UserId,
         uc.DisplayName,
         uc.Reputation,
         uc.Questions,
         uc.Answers,
         uc.Badges,
         uc.Gold,
         uc.Silver,
         uc.Bronze,
         uc.UpVotesGiven,
         uc.CommentsMade,
         row_number() OVER (ORDER BY uc.Reputation DESC NULLS LAST, uc.Answers DESC NULLS LAST) AS user_rank
  FROM user_complex uc
)
SELECT
  f.UserId,
  f.DisplayName,
  f.Reputation,
  f.Questions,
  f.Answers,
  f.Badges,
  f.Gold,
  f.Silver,
  f.Bronze,
  f.UpVotesGiven,
  f.CommentsMade,
  COALESCE((SELECT count(*) FROM Posts p WHERE p.OwnerUserId = f.UserId AND p.PostTypeId = 1 AND p.CreationDate > now() - INTERVAL '1 year'), 0) AS QuestionsLastYear,
  COALESCE((SELECT max(v.CreationDate) FROM Votes v WHERE v.UserId = f.UserId), to_timestamp(0)) AS LastVoteDate,
  a.anomaly,
  a.Title AS AnomalousPostTitle,
  t.key AS TopListKey,
  t.val AS TopListVal
FROM final_users f
LEFT JOIN LATERAL (
  SELECT anomaly, Title, Id
  FROM anomalies
  WHERE anomalies.OwnerUserId = f.UserId AND anomalies.anomaly <> 'NORMAL'
  ORDER BY anomaly, Id
  LIMIT 1
) a ON true
LEFT JOIN LATERAL (
  SELECT key, val
  FROM top_lists tl
  WHERE tl.kind = 'top_user' AND tl.key = f.DisplayName
  LIMIT 1
) t ON true
WHERE f.user_rank <= 50
ORDER BY f.user_rank
UNION
-- a supplementary result set showcasing hottest questions per month with windowing + NULL logic
SELECT
  NULL::int AS UserId,
  h.Title AS DisplayName,
  NULL::int AS Reputation,
  NULL::int AS Questions,
  NULL::int AS Answers,
  NULL::int AS Badges,
  NULL::int AS Gold,
  NULL::int AS Silver,
  NULL::int AS Bronze,
  NULL::int AS UpVotesGiven,
  NULL::int AS CommentsMade,
  NULL::int AS QuestionsLastYear,
  NULL::timestamp AS LastVoteDate,
  'HOT_QUESTION' AS anomaly,
  NULL::text AS AnomalousPostTitle,
  ('month-' || to_char(h.CreationDate,'YYYY-MM'))::text AS TopListKey,
  ('rank:' || h.monthly_rank || '|score:' || COALESCE(h.Score,0) || '|views:' || COALESCE(h.ViewCount,0))::text AS TopListVal
FROM hot_questions h
WHERE h.monthly_rank = 1
ORDER BY TopListKey DESC, TopListVal DESC;