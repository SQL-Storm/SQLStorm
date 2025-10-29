-- {"query": "5996.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 671}
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC
    ) AS rn_by_owner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2)
    AND p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180' DAY
),
owner_summary AS (
  SELECT
    rp.OwnerUserId,
    MAX(rp.Reputation) AS max_reputation,
    MIN(rp.OwnerCreationDate) AS first_created,
    COUNT(*) AS posts_owned_in_last_180
  FROM ranked_posts rp
  GROUP BY rp.OwnerUserId
),
complex_filter AS (
  SELECT
    rp.*,
    CASE
      WHEN rp.Score > 20 THEN 'high'
      WHEN rp.Score BETWEEN 5 AND 20 THEN 'medium'
      ELSE 'low'
    END AS score_category
  FROM ranked_posts rp
)
SELECT
  cf.PostId,
  cf.PostTypeId,
  cf.OwnerUserId,
  cf.Title,
  cf.Tags,
  cf.CreationDate,
  cf.LastActivityDate,
  cf.Score,
  cf.ViewCount,
  cf.CommentCount,
  cf.AnswerCount,
  cf.FavoriteCount,
  cf.ContentLicense,
  cf.OwnerDisplayName,
  cf.Reputation,
  cf.OwnerCreationDate,
  cf.OwnerLastAccessDate,
  cf.rn_by_owner,
  cf.score_category,
  os.max_reputation,
  os.first_created,
  os.posts_owned_in_last_180
FROM complex_filter cf
LEFT JOIN owner_summary os ON cf.OwnerUserId = os.OwnerUserId
WHERE cf.rn_by_owner = 1
GROUP BY
  cf.PostId,
  cf.PostTypeId,
  cf.OwnerUserId,
  cf.Title,
  cf.Tags,
  cf.CreationDate,
  cf.LastActivityDate,
  cf.Score,
  cf.ViewCount,
  cf.CommentCount,
  cf.AnswerCount,
  cf.FavoriteCount,
  cf.ContentLicense,
  cf.OwnerDisplayName,
  cf.Reputation,
  cf.OwnerCreationDate,
  cf.OwnerLastAccessDate,
  cf.rn_by_owner,
  cf.score_category,
  os.max_reputation,
  os.first_created,
  os.posts_owned_in_last_180;