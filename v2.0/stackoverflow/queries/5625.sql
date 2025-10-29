-- {"query": "5625.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 836}
WITH recent_questions AS (
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
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
),
-- For portability: treat each Tags field as a single tag entry if robust splitting is not available.
top_tags AS (
  SELECT
    tag,
    AVG(score) AS avg_score,
    COUNT(*) AS questions_count
  FROM (
    SELECT
      p.Score AS score,
      -- normalized_tags: tags without leading '<' and trailing '>'
      CASE
        WHEN p.Tags IS NULL THEN NULL
        WHEN LENGTH(p.Tags) >= 2 AND SUBSTR(p.Tags,1,1) = '<' AND SUBSTR(p.Tags, -1, 1) = '>' THEN SUBSTR(p.Tags, 2, LENGTH(p.Tags) - 2)
        ELSE p.Tags
      END AS normalized_tags
    FROM recent_questions p
  ) p
  CROSS JOIN LATERAL (
    -- Simple, portable splitting fallback: if normalized_tags is NULL then no rows; else return normalized_tags as one tag.
    SELECT TRIM(s) AS tag
    FROM (
      SELECT
        CASE WHEN p.normalized_tags IS NULL THEN NULL ELSE p.normalized_tags END AS s
    ) t
    WHERE t.s IS NOT NULL AND TRIM(t.s) <> ''
  ) split
  GROUP BY tag
),
tag_trends AS (
  SELECT
    t.tag,
    t.avg_score,
    t.questions_count,
    ROW_NUMBER() OVER (ORDER BY t.questions_count DESC, t.avg_score DESC) AS rn
  FROM top_tags t
),
activity_by_user AS (
  SELECT
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes_received,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes_received,
    SUM(p.ViewCount) AS total_views_by_user,
    MAX(p.LastActivityDate) AS last_activity
  FROM Posts p
  INNER JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY p.OwnerUserId, u.DisplayName
),
complex_post AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.LastEditorUserId,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerName,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS total_comments,
    (SELECT MAX(CreationDate) FROM Votes v WHERE v.PostId = p.Id) AS last_vote_date,
    COALESCE(p.Score, 0) AS computed_score
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2)
),
filtered AS (
  SELECT
    c.*,
    ROW_NUMBER() OVER (PARTITION BY c.OwnerUserId ORDER BY c.CreationDate DESC, c.Score DESC) AS rn_owner
  FROM complex_post c
  WHERE c.LastActivityDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
)
SELECT
  r.PostId,
  r.Title,
  r.Tags,
  r.CreationDate,
  r.Score,
  r.ViewCount,
  r.OwnerUserId,
  r.OwnerDisplayName,
  r.LastActivityDate,
  r.CommentCount,
  r.AnswerCount,
  r.FavoriteCount,
  r.ContentLicense,
  r.Reputation,
  r.OwnerDisplayName AS OwnerName,
  a.total_views_by_user,
  a.last_activity,
  t.tag AS top_tag,
  t.avg_score AS top_tag_avg_score,
  t.questions_count AS top_tag_questions
FROM recent_questions r
LEFT JOIN activity_by_user a ON r.OwnerUserId = a.OwnerUserId
LEFT JOIN tag_trends t ON t.rn = 1
ORDER BY r.LastActivityDate DESC
LIMIT 100;