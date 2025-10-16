-- {"query": "26079.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 650} 
WITH ranked_posts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS score_rank,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS view_rank
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL
),
top_voters AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    COUNT(v.Id) AS vote_count,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvote_count,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvote_count
  FROM 
    Users u
  JOIN 
    Votes v ON u.Id = v.UserId
  GROUP BY 
    u.Id, u.DisplayName
  HAVING 
    COUNT(v.Id) > 1000
),
closed_posts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    ph.Comment AS close_reason,
    ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS close_rank
  FROM 
    Posts p
  JOIN 
    PostHistory ph ON p.Id = ph.PostId
  WHERE 
    ph.PostHistoryTypeId = 10 AND p.ClosedDate IS NOT NULL
)
SELECT 
  p.Id, 
  p.Score, 
  p.ViewCount, 
  p.Title, 
  u.DisplayName AS owner_name,
  COALESCE(u.Reputation, 0) AS owner_reputation,
  COALESCE(rp.score_rank, 0) AS score_rank,
  COALESCE(rp.view_rank, 0) AS view_rank,
  COALESCE(tv.vote_count, 0) AS owner_vote_count,
  COALESCE(cp.close_reason, '') AS close_reason,
  STRING_AGG(DISTINCT t.TagName, ', ') AS tags,
  COUNT(DISTINCT c.Id) AS comment_count
FROM 
  Posts p
LEFT JOIN 
  Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
  ranked_posts rp ON p.Id = rp.Id
LEFT JOIN 
  top_voters tv ON u.Id = tv.Id
LEFT JOIN 
  closed_posts cp ON p.Id = cp.Id AND cp.close_rank = 1
LEFT JOIN 
  PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
  Posts related_p ON pl.RelatedPostId = related_p.Id
LEFT JOIN 
  Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
  Comments c ON p.Id = c.PostId
WHERE 
  p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL
GROUP BY 
  p.Id, p.Score, p.ViewCount, p.Title, u.DisplayName, u.Reputation, rp.score_rank, rp.view_rank, tv.vote_count, cp.close_reason
ORDER BY 
  p.Score DESC, p.ViewCount DESC
LIMIT 100;