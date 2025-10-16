-- {"query": "26008.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 536} 
WITH ranked_posts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS score_rank,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS view_rank,
    ROW_NUMBER() OVER (ORDER BY p.AnswerCount DESC) AS answer_rank,
    ROW_NUMBER() OVER (ORDER BY p.CommentCount DESC) AS comment_rank
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1
),
top_posters AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    COUNT(p.Id) AS post_count,
    SUM(p.Score) AS total_score,
    ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC) AS score_rank
  FROM 
    Users u
  JOIN 
    Posts p ON u.Id = p.OwnerUserId
  WHERE 
    p.PostTypeId = 1
  GROUP BY 
    u.Id, u.DisplayName
),
badge_counts AS (
  SELECT 
    u.Id, 
    COUNT(b.Id) AS badge_count
  FROM 
    Users u
  JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    u.Id
)
SELECT 
  p.Id, 
  p.Title, 
  p.Score, 
  p.ViewCount, 
  p.AnswerCount, 
  p.CommentCount, 
  rp.score_rank, 
  rp.view_rank, 
  rp.answer_rank, 
  rp.comment_rank,
  u.DisplayName AS owner_name,
  u.Reputation AS owner_reputation,
  tp.post_count, 
  tp.total_score, 
  bc.badge_count,
  ph.Comment AS close_reason,
  COALESCE(v.VoteTypeId, 0) AS vote_type
FROM 
  Posts p
JOIN 
  ranked_posts rp ON p.Id = rp.Id
JOIN 
  Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
  top_posters tp ON u.Id = tp.Id
LEFT JOIN 
  badge_counts bc ON u.Id = bc.Id
LEFT JOIN 
  PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN 
  Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2
WHERE 
  p.PostTypeId = 1 AND p.Score > 0
ORDER BY 
  rp.score_rank, rp.view_rank, rp.answer_rank, rp.comment_rank;