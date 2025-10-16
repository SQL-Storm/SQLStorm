-- {"query": "26095.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 654} 

WITH ranked_posts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS score_rank,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS view_rank,
    ROW_NUMBER() OVER (ORDER BY p.CommentCount DESC) AS comment_rank,
    ROW_NUMBER() OVER (ORDER BY p.FavoriteCount DESC) AS favorite_rank
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
    CommentCount, 
    FavoriteCount, 
    score_rank, 
    view_rank, 
    comment_rank, 
    favorite_rank
  FROM 
    ranked_posts
  WHERE 
    score_rank <= 10 OR view_rank <= 10 OR comment_rank <= 10 OR favorite_rank <= 10
),
user_reputation AS (
  SELECT 
    u.Id, 
    u.Reputation, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
  FROM 
    Users u
  LEFT JOIN 
    Votes v ON u.Id = v.UserId
  GROUP BY 
    u.Id, u.Reputation
),
post_history_stats AS (
  SELECT 
    ph.PostId, 
    COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS close_votes, 
    COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE NULL END) AS reopen_votes
  FROM 
    PostHistory ph
  GROUP BY 
    ph.PostId
)
SELECT 
  p.Id, 
  p.Title, 
  p.Score, 
  p.ViewCount, 
  p.CommentCount, 
  p.FavoriteCount, 
  ur.Reputation, 
  ur.upvotes, 
  ur.downvotes, 
  phs.close_votes, 
  phs.reopen_votes,
  CASE 
    WHEN p.Score > 100 AND p.ViewCount > 1000 THEN 'Highly Rated and Viewed'
    WHEN p.Score > 50 AND p.ViewCount > 500 THEN 'Well Rated and Viewed'
    ELSE 'Low Rated and Viewed'
  END AS post_rating,
  CASE 
    WHEN ur.Reputation > 10000 THEN 'High Reputation'
    WHEN ur.Reputation > 5000 THEN 'Medium Reputation'
    ELSE 'Low Reputation'
  END AS user_reputation_level
FROM 
  top_10_posts p
JOIN 
  Users u ON p.OwnerUserId = u.Id
JOIN 
  user_reputation ur ON u.Id = ur.Id
LEFT JOIN 
  post_history_stats phs ON p.Id = phs.PostId
ORDER BY 
  p.score_rank, p.view_rank, p.comment_rank, p.favorite_rank;
