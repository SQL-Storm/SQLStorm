-- {"query": "56084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 504} 
WITH ranked_posts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.Tags, 
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS score_rank,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS view_rank
  FROM Posts p
  WHERE p.PostTypeId = 1
),
top_scored_posts AS (
  SELECT Id, Score, ViewCount, Tags
  FROM ranked_posts
  WHERE score_rank <= 10
),
top_viewed_posts AS (
  SELECT Id, Score, ViewCount, Tags
  FROM ranked_posts
  WHERE view_rank <= 10
),
post_votes AS (
  SELECT 
    p.Id, 
    COUNT(v.VoteTypeId) AS vote_count, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvote_count, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvote_count
  FROM Posts p
  JOIN Votes v ON p.Id = v.PostId
  GROUP BY p.Id
),
post_comments AS (
  SELECT 
    p.Id, 
    COUNT(c.Id) AS comment_count
  FROM Posts p
  JOIN Comments c ON p.Id = c.PostId
  GROUP BY p.Id
)
SELECT 
  tp.Id, 
  tp.Score, 
  tp.ViewCount, 
  tp.Tags, 
  pv.vote_count, 
  pv.upvote_count, 
  pv.downvote_count, 
  pc.comment_count,
  u.DisplayName AS owner_display_name,
  u.Reputation AS owner_reputation
FROM top_scored_posts tp
JOIN post_votes pv ON tp.Id = pv.Id
JOIN post_comments pc ON tp.Id = pc.Id
JOIN Users u ON tp.Id = u.Id
UNION ALL
SELECT 
  tp.Id, 
  tp.Score, 
  tp.ViewCount, 
  tp.Tags, 
  pv.vote_count, 
  pv.upvote_count, 
  pv.downvote_count, 
  pc.comment_count,
  u.DisplayName AS owner_display_name,
  u.Reputation AS owner_reputation
FROM top_viewed_posts tp
JOIN post_votes pv ON tp.Id = pv.Id
JOIN post_comments pc ON tp.Id = pc.Id
JOIN Users u ON tp.Id = u.Id
ORDER BY Id;