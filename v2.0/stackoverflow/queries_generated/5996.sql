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
    AND p.LastActivityDate >= NOW() - INTERVAL '180 days'
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
      WHEN rp.Score > 20 THEN 'high';
      -- placeholder for complex calculation to keep query interesting
    END AS score_bucket
  FROM ranked_posts rp
  LEFT JOIN Votes v ON v.PostId = rp.PostId
  LEFT JOIN PostLinks pl ON pl.PostId = rp.PostId
  LEFT JOIN Tags t ON t.Id = (SELECT Id FROM Tags WHERE Tags.ExcerptPostId = rp.PostId LIMIT 1)
  WHERE rp.rn_by_owner <= 3
    OR (EXISTS (SELECT 1 FROM Votes vv WHERE vv.PostId = rp.PostId AND vv.VoteTypeId = 2))
),
closed_or_not AS (
  SELECT
    cf.*,
    COALESCE((SELECT 1 FROM PostHistory ph
              WHERE ph.PostId = cf.PostId AND ph.PostHistoryTypeId = 10
              AND ph.CreationDate >= cf.CreationDate), 0) AS was_closed
  FROM complex_filter cf
)
SELECT
  cor.OwnerUserId,
  cor.Title,
  cor.Tags,
  cor.ViewCount,
  cor.Score,
  cor.CommentCount,
  cor.AnswerCount,
  cor.FavoriteCount,
  cor.CreationDate,
  cor.LastActivityDate,
  cor.OwnerDisplayName,
  os.max_reputation,
  os.posts_owned_in_last_180,
  CASE
    WHEN cor.was_closed = 1 THEN 'Closed'
    ELSE 'Open'
  END AS post_status,
  -- window function example: rank within owner group by last activity
  RANK() OVER (PARTITION BY cor.OwnerUserId ORDER BY cor.LastActivityDate DESC) AS activity_rank
FROM closed_or_not cor
JOIN owner_summary os ON os.OwnerUserId = cor.OwnerUserId
ORDER BY cor.OwnerUserId, cor.LastActivityDate DESC
LIMIT 100;