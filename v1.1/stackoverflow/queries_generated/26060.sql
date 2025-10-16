-- {"query": "26060.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 452} 

WITH ranked_posts AS (
  SELECT 
    p.Id,
    p.Score,
    p.ViewCount,
    p.Tags,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS score_rank,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS view_rank
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1 AND p.Score > 0 AND p.ViewCount > 0
),
top_100_posts AS (
  SELECT 
    Id,
    Score,
    ViewCount,
    Tags,
    score_rank,
    view_rank
  FROM 
    ranked_posts
  WHERE 
    score_rank <= 100 OR view_rank <= 100
),
user_badges AS (
  SELECT 
    u.Id,
    COUNT(DISTINCT b.Name) AS badge_count
  FROM 
    Users u
  LEFT JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    u.Id
),
post_votes AS (
  SELECT 
    p.Id,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes
  FROM 
    Posts p
  LEFT JOIN 
    Votes v ON p.Id = v.PostId
  GROUP BY 
    p.Id
)
SELECT 
  p.Id,
  p.Score,
  p.ViewCount,
  p.Tags,
  u.DisplayName,
  u.Reputation,
  ub.badge_count,
  pv.up_votes,
  pv.down_votes,
  ph.Comment,
  ph.Text
FROM 
  top_100_posts p
JOIN 
  Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
  user_badges ub ON u.Id = ub.Id
LEFT JOIN 
  post_votes pv ON p.Id = pv.Id
LEFT JOIN 
  PostHistory ph ON p.Id = ph.PostId
WHERE 
  ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL AND ph.Text IS NOT NULL
ORDER BY 
  p.score_rank, p.view_rank, u.Reputation DESC;
