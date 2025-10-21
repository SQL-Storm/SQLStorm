WITH 
latest_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2)
),
tag_expansion AS (
  SELECT
    p.Id AS pid,
    (CASE WHEN p.Tags IS NULL THEN 0 ELSE
      (SELECT COUNT(*) FROM unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName))
      END) AS tag_count
  FROM Posts p
),
tag_popularity AS (
  SELECT
    p.Id AS post_id,
    COUNT(*) AS tag_post_count
  FROM Posts p
  LEFT JOIN LATERAL unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName) ON TRUE
  GROUP BY p.Id
),
hot_posts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.LastActivityDate,
    p.Tags
  FROM Posts p
  WHERE p.LastActivityDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
)
SELECT
  lp.PostId,
  lp.Title,
  lp.PostTypeId,
  lp.OwnerUserId,
  u.DisplayName,
  lp.ViewCount,
  lp.Score,
  lp.CommentCount,
  lp.LastActivityDate,
  COALESCE(tp.tag_post_count, 0) AS tag_popularity,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = lp.PostId AND c.Score > 0) AS positive_comments,
  (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.PostId = lp.PostId) AS last_comment_date
FROM latest_posts lp
LEFT JOIN Users u ON lp.OwnerUserId = u.Id
LEFT JOIN tag_popularity tp ON tp.post_id = lp.PostId
LEFT JOIN tag_expansion te ON te.pid = lp.PostId
WHERE lp.rn = 1

UNION ALL

SELECT
  hp.Id AS PostId,
  hp.Title,
  hp.PostTypeId,
  hp.OwnerUserId,
  u2.DisplayName,
  hp.ViewCount,
  hp.Score,
  hp.CommentCount,
  hp.LastActivityDate,
  CAST(NULL AS INTEGER) AS tag_popularity,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = hp.Id AND c.Score > 0) AS positive_comments,
  (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.PostId = hp.Id) AS last_comment_date
FROM hot_posts hp
LEFT JOIN Users u2 ON hp.OwnerUserId = u2.Id
ORDER BY LastActivityDate DESC
LIMIT 200;