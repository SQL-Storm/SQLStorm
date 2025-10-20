-- {"query": "115.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1329} 
WITH q AS (
  SELECT
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.Tags
  FROM Posts p
  WHERE p.PostTypeId = 1
),
owner_rank AS (
  SELECT
    q.*,
    ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.Score DESC, q.ViewCount DESC) AS rank_by_owner
  FROM q
),
votes_agg AS (
  SELECT
    orq.Id,
    orq.Title,
    orq.Score,
    orq.ViewCount,
    orq.CreationDate,
    orq.OwnerUserId,
    orq.Tags,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS recent_upvotes
  FROM owner_rank orq
  LEFT JOIN Votes v
    ON v.PostId = orq.Id
   AND v.CreationDate > (CURRENT_DATE - INTERVAL '30 days')
  GROUP BY orq.Id, orq.Title, orq.Score, orq.ViewCount, orq.CreationDate, orq.OwnerUserId, orq.Tags
)
SELECT
  vq.Id AS post_id,
  vq.Title,
  vq.Score,
  vq.ViewCount,
  vq.CreationDate,
  u.DisplayName AS OwnerDisplayName,
  vq.recent_upvotes,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = vq.Id) AS link_count,
  pl.RelatedPostId AS related_post_id,
  rp.Title AS related_post_title,
  rp.Score AS related_post_score
FROM votes_agg vq
LEFT JOIN Users u ON u.Id = vq.OwnerUserId
LEFT JOIN PostLinks pl ON pl.PostId = vq.Id AND pl.LinkTypeId = 1
LEFT JOIN Posts rp ON rp.Id = pl.RelatedPostId
ORDER BY vq.Score DESC, vq.ViewCount DESC
LIMIT 200
;