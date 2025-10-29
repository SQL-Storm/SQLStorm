-- {"query": "5456.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 654} 
WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    U.DisplayName AS OwnerName,
    U.Reputation,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_owner
  FROM Posts p
  LEFT JOIN Users U ON p.OwnerUserId = U.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
activity_window AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Tags,
    rq.CreationDate,
    rq.ViewCount,
    rq.OwnerUserId,
    rq.OwnerName,
    rq.Reputation,
    rq.LastActivityDate,
    rq.CommentCount,
    rq.AnswerCount,
    rq.Score,
    ROW_NUMBER() OVER (
      PARTITION BY rq.OwnerUserId
      ORDER BY rq.LastActivityDate DESC, rq.CreationDate DESC
    ) AS rn_owner_activity
  FROM recent_questions rq
),
tag_summary AS (
  SELECT
    t.TagName,
    COUNT(*) AS tag_count,
    AVG(p.Score) AS avg_score,
    SUM(p.ViewCount) AS total_views
  FROM (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
           p.Id
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) q
  JOIN Posts p ON p.Id = q.Id
  JOIN Tags t ON t.TagName = q.TagName
  GROUP BY t.TagName
)
SELECT
  aw.PostId,
  aw.Title,
  aw.Tags,
  aw.CreationDate,
  aw.LastActivityDate,
  aw.ViewCount,
  aw.Score,
  aw.OwnerName,
  aw.Reputation,
  aw.CommentCount,
  aw.AnswerCount,
  ts.tag_count,
  ts.avg_score,
  ts.total_views,
  -- Derived metrics and complex predicates
  CASE
    WHEN aw.Reputation > 2000 THEN 'HighRep'
    WHEN aw.Reputation BETWEEN 500 AND 2000 THEN 'MidRep'
    ELSE 'NewOrLowRep'
  END AS owner_rep_band,
  CASE
    WHEN aw.LastActivityDate > NOW() - INTERVAL '30 days' THEN true
    ELSE false
  END AS active_recent,
  -- Correlated subquery: number of comments on the post
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = aw.PostId) AS comment_count_total,
  -- Window function usage: rank of owner by activity
  aw.rn_owner_activity AS owner_activity_rank
FROM activity_window aw
LEFT JOIN tag_summary ts ON true
WHERE aw.rn_owner_activity <= 5
ORDER BY aw.LastActivityDate DESC NULLS LAST, aw.ViewCount DESC, aw.Score DESC
LIMIT 100;