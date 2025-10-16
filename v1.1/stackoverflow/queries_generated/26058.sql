-- {"query": "26058.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 595} 

WITH ranked_posts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.Tags, 
    p.LastActivityDate, 
    p.LastEditDate, 
    p.AcceptedAnswerId, 
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS score_rank,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS view_rank
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1 AND p.ClosedDate IS NULL
),
top_10_posts AS (
  SELECT 
    Id, 
    Score, 
    ViewCount, 
    Tags, 
    LastActivityDate, 
    LastEditDate, 
    AcceptedAnswerId, 
    score_rank, 
    view_rank
  FROM 
    ranked_posts
  WHERE 
    score_rank <= 10 OR view_rank <= 10
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
),
post_badges AS (
  SELECT 
    p.Id, 
    COUNT(DISTINCT b.Name) AS badge_count
  FROM 
    Posts p
  LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
  LEFT JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    p.Id
)
SELECT 
  tp.Id, 
  tp.Score, 
  tp.ViewCount, 
  tp.Tags, 
  tp.LastActivityDate, 
  tp.LastEditDate, 
  tp.AcceptedAnswerId, 
  tp.score_rank, 
  tp.view_rank, 
  pv.up_votes, 
  pv.down_votes, 
  pb.badge_count,
  COUNT(DISTINCT pl.RelatedPostId) AS related_post_count
FROM 
  top_10_posts tp
LEFT JOIN 
  post_votes pv ON tp.Id = pv.Id
LEFT JOIN 
  post_badges pb ON tp.Id = pb.Id
LEFT JOIN 
  PostLinks pl ON tp.Id = pl.PostId AND pl.LinkTypeId = 1
GROUP BY 
  tp.Id, 
  tp.Score, 
  tp.ViewCount, 
  tp.Tags, 
  tp.LastActivityDate, 
  tp.LastEditDate, 
  tp.AcceptedAnswerId, 
  tp.score_rank, 
  tp.view_rank, 
  pv.up_votes, 
  pv.down_votes, 
  pb.badge_count
ORDER BY 
  tp.score_rank, 
  tp.view_rank;
