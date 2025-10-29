-- {"query": "5565.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 630}
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    COALESCE(p.Body, '') AS Body
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
),
top_tags AS (
  SELECT
    unnest(string_to_array(substring(rq.Tags FROM 2 FOR length(rq.Tags)-2), '><')) AS tag,
    rq.PostId AS PostId,
    rq.Score
  FROM recent_questions rq
),
tag_score AS (
  SELECT
    tag,
    AVG(Score) AS avg_post_score,
    MIN(CreationDate) AS first_post_date,
    MAX(LastActivityDate) AS last_activity
  FROM (
    SELECT
      tt.tag,
      rq.Score,
      rq.CreationDate,
      rq.LastActivityDate
    FROM top_tags tt
    JOIN recent_questions rq ON rq.PostId = tt.PostId
  ) t
  GROUP BY tag
),
comments_per_post AS (
  SELECT
    c.PostId,
    COUNT(*) AS comment_count,
    AVG(LENGTH(c.Text)) AS avg_comment_len
  FROM Comments c
  GROUP BY c.PostId
),
top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.AccountId,
    u.LastAccessDate,
    u.CreationDate
  FROM Users u
  WHERE u.Reputation > 10000
),
aggregate AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.OwnerUserId,
    rq.Tags,
    rq.ViewCount,
    rq.Score,
    COALESCE(c.comment_count, 0) AS comment_count,
    COALESCE(ts.avg_post_score, 0) AS avg_tag_score,
    COALESCE(ts.last_activity, rq.LastActivityDate) AS last_activity
  FROM recent_questions rq
  LEFT JOIN comments_per_post c ON c.PostId = rq.PostId
  LEFT JOIN (
    -- aggregate tag scores per post by joining tag_score to top_tags to recent_questions
    SELECT tt.PostId, t.avg_post_score, t.last_activity
    FROM top_tags tt
    JOIN tag_score t ON t.tag = tt.tag
  ) ts ON ts.PostId = rq.PostId
)
SELECT
  a.PostId,
  a.Title,
  a.OwnerUserId,
  a.CreationDate AS CreateDate,
  a.Tags,
  a.ViewCount,
  a.Score,
  a.comment_count,
  a.avg_tag_score,
  a.last_activity,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation
FROM aggregate a
LEFT JOIN top_users u ON u.UserId = a.OwnerUserId
GROUP BY
  a.PostId,
  a.Title,
  a.OwnerUserId,
  a.CreationDate,
  a.Tags,
  a.ViewCount,
  a.Score,
  a.comment_count,
  a.avg_tag_score,
  a.last_activity,
  u.DisplayName,
  u.Reputation
ORDER BY a.last_activity DESC, a.Score DESC
LIMIT 200;