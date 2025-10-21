-- {"query": "26013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 695} 
WITH ranked_posts AS (
  SELECT 
    p.Id,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS score_rank,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS view_rank
  FROM Posts p
),
top_scored_posts AS (
  SELECT 
    rp.Id,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.OwnerUserId,
    u.DisplayName AS owner_name,
    u.Reputation AS owner_reputation
  FROM ranked_posts rp
  JOIN Users u ON rp.OwnerUserId = u.Id
  WHERE rp.score_rank <= 5
),
top_viewed_posts AS (
  SELECT 
    rp.Id,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.OwnerUserId,
    u.DisplayName AS owner_name,
    u.Reputation AS owner_reputation
  FROM ranked_posts rp
  JOIN Users u ON rp.OwnerUserId = u.Id
  WHERE rp.view_rank <= 5
),
user_badges AS (
  SELECT 
    u.Id,
    COUNT(b.Id) AS badge_count,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges
  FROM Users u
  LEFT JOIN Badges b ON u.Id = b.UserId
  GROUP BY u.Id
),
post_votes AS (
  SELECT 
    p.Id,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes
  FROM Posts p
  LEFT JOIN Votes v ON p.Id = v.PostId
  GROUP BY p.Id
)
SELECT 
  p.Id,
  p.Score,
  p.ViewCount,
  p.Tags,
  p.OwnerUserId,
  u.DisplayName AS owner_name,
  u.Reputation AS owner_reputation,
  tsp.Score AS top_score,
  tsp.ViewCount AS top_view,
  ub.badge_count,
  ub.gold_badges,
  ub.silver_badges,
  ub.bronze_badges,
  pv.up_votes,
  pv.down_votes,
  ph.Comment AS post_history_comment,
  pt.Name AS post_type,
  COALESCE(pl.RelatedPostId, 0) AS related_post_id
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN top_scored_posts tsp ON p.Id = tsp.Id
LEFT JOIN top_viewed_posts tvp ON p.Id = tvp.Id
LEFT JOIN user_badges ub ON u.Id = ub.Id
LEFT JOIN post_votes pv ON p.Id = pv.Id
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
WHERE p.Score > 10 AND p.ViewCount > 100
ORDER BY p.Score DESC, p.ViewCount DESC;