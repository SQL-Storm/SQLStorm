-- {"query": "26047.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 750} 

WITH ranked_posts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.Title, 
    p.Tags, 
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS score_rank,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC) AS view_rank
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1 AND p.Score > 0 AND p.ViewCount > 0
),
top_answerers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    COUNT(DISTINCT a.Id) AS answer_count,
    SUM(a.Score) AS total_score
  FROM 
    Users u
  JOIN 
    Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
  GROUP BY 
    u.Id, u.DisplayName
  HAVING 
    COUNT(DISTINCT a.Id) > 10 AND SUM(a.Score) > 100
),
post_history_summary AS (
  SELECT 
    ph.PostId, 
    COUNT(DISTINCT ph.PostHistoryTypeId) AS history_count,
    MAX(ph.CreationDate) AS last_update
  FROM 
    PostHistory ph
  GROUP BY 
    ph.PostId
)
SELECT 
  p.Id, 
  p.Title, 
  p.Tags, 
  p.Score, 
  p.ViewCount, 
  u.DisplayName AS owner_name, 
  u.Reputation AS owner_reputation,
  COALESCE(tas.answer_count, 0) AS answer_count,
  COALESCE(tas.total_score, 0) AS total_score,
  phs.history_count, 
  phs.last_update,
  CASE 
    WHEN p.Score > 100 AND p.ViewCount > 1000 THEN 'High'
    WHEN p.Score > 50 AND p.ViewCount > 500 THEN 'Medium'
    ELSE 'Low'
  END AS engagement_level,
  CASE 
    WHEN u.Reputation > 10000 THEN 'Expert'
    WHEN u.Reputation > 1000 THEN 'Advanced'
    ELSE 'Beginner'
  END AS owner_level,
  LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) AS prev_score,
  LEAD(p.ViewCount, 1) OVER (ORDER BY p.CreationDate) AS next_view_count,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvote_count,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvote_count,
  COALESCE(rp.score_rank, 0) AS score_rank,
  COALESCE(rp.view_rank, 0) AS view_rank
FROM 
  Posts p
JOIN 
  Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
  top_answerers tas ON u.Id = tas.Id
LEFT JOIN 
  post_history_summary phs ON p.Id = phs.PostId
LEFT JOIN 
  ranked_posts rp ON p.Id = rp.Id
LEFT JOIN 
  Votes v ON p.Id = v.PostId
WHERE 
  p.PostTypeId = 1 AND p.Score > 0 AND p.ViewCount > 0
GROUP BY 
  p.Id, p.Title, p.Tags, p.Score, p.ViewCount, u.DisplayName, u.Reputation, tas.answer_count, tas.total_score, phs.history_count, phs.last_update, rp.score_rank, rp.view_rank
ORDER BY 
  p.Score DESC, p.ViewCount DESC;
