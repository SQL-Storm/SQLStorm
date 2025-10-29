-- {"query": "5952.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 811}
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayNameSQL,
    u.UpVotes,
    u.DownVotes,
    w.Name AS PostTypeName
  FROM Posts p
  LEFT JOIN PostTypes w ON p.PostTypeId = w.Id
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2)
),
cte_recent_activity AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.Score,
    rp.ViewCount,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.PostTypeId,
    rp.ParentId,
    rp.AcceptedAnswerId,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ContentLicense,
    rp.Reputation
  FROM ranked_posts rp
  WHERE rp.LastActivityDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
),
corr AS (
  SELECT
    c.PostId,
    c.Title,
    c.Tags,
    c.Score,
    c.ViewCount,
    c.CreationDate,
    c.LastActivityDate,
    c.OwnerUserId,
    c.OwnerDisplayName,
    c.PostTypeId,
    c.ParentId,
    c.AcceptedAnswerId,
    c.CommentCount,
    c.FavoriteCount,
    c.ContentLicense,
    c.Reputation,
    ROW_NUMBER() OVER (ORDER BY c.LastActivityDate DESC, c.Score DESC) AS rn
  FROM cte_recent_activity c
),
window_stats AS (
  SELECT
    PostId,
    Title,
    Tags,
    Score,
    ViewCount,
    CreationDate,
    LastActivityDate,
    OwnerUserId,
    OwnerDisplayName,
    PostTypeId,
    ParentId,
    AcceptedAnswerId,
    CommentCount,
    FavoriteCount,
    ContentLicense,
    Reputation,
    rn,
    SUM(1) OVER (
      PARTITION BY PostTypeId
      ORDER BY LastActivityDate DESC
      ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING
    ) AS neighbor_count
  FROM corr
),
enhanced AS (
  SELECT
    w.PostId,
    w.Title,
    w.Tags,
    w.Score,
    w.ViewCount,
    w.CreationDate,
    w.LastActivityDate,
    w.OwnerUserId,
    w.OwnerDisplayName,
    w.PostTypeId,
    w.ParentId,
    w.AcceptedAnswerId,
    w.CommentCount,
    w.FavoriteCount,
    w.ContentLicense,
    w.Reputation,
    w.rn,
    w.neighbor_count,
    CASE
      WHEN w.PostTypeId = 1 THEN 'Question'
      WHEN w.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS TypeLabel,
    (w.Score * 2 + w.ViewCount / NULLIF(CAST(w.Reputation AS DOUBLE PRECISION), 0)) AS composite_score,
    LOWER(REGEXP_REPLACE(w.Tags, '[<>]', '', 'g')) AS normalized_tags
  FROM window_stats w
)
SELECT
  enhanced.PostId,
  enhanced.Title,
  enhanced.Tags,
  enhanced.ViewCount,
  enhanced.Score,
  enhanced.LastActivityDate,
  enhanced.CreationDate,
  enhanced.OwnerUserId,
  enhanced.OwnerDisplayName,
  enhanced.TypeLabel,
  enhanced.composite_score,
  enhanced.neighbor_count,
  enhanced.Reputation,
  enhanced.normalized_tags
FROM enhanced
LEFT JOIN Badges b
  ON b.UserId = enhanced.OwnerUserId
WHERE
  (enhanced.PostTypeId = 1 AND enhanced.CommentCount > 5)
  OR (enhanced.PostTypeId = 2 AND enhanced.Score > 0)
  OR (enhanced.normalized_tags LIKE '%sql%' OR enhanced.normalized_tags LIKE '%performance%')
ORDER BY enhanced.composite_score DESC, enhanced.LastActivityDate DESC
LIMIT 100;