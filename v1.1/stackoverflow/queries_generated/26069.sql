-- {"query": "26069.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 614} 

WITH ranked_posts AS (
  SELECT 
    p.Id,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS score_rank,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC) AS view_rank
  FROM 
    Posts p
  WHERE 
    p.PostTypeId IN (1, 2)
),
top_scored_posts AS (
  SELECT 
    Id,
    PostTypeId,
    Score,
    ViewCount,
    LastActivityDate,
    score_rank,
    view_rank
  FROM 
    ranked_posts
  WHERE 
    score_rank <= 10
),
top_viewed_posts AS (
  SELECT 
    Id,
    PostTypeId,
    Score,
    ViewCount,
    LastActivityDate,
    score_rank,
    view_rank
  FROM 
    ranked_posts
  WHERE 
    view_rank <= 10
),
post_tags AS (
  SELECT 
    p.Id,
    STRING_AGG(t.TagName, ', ') AS tags
  FROM 
    Posts p
  JOIN 
    PostLinks pl ON p.Id = pl.PostId
  JOIN 
    Tags t ON pl.RelatedPostId = t.Id
  GROUP BY 
    p.Id
),
post_votes AS (
  SELECT 
    p.Id,
    COUNT(v.Id) AS vote_count,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvote_count,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvote_count
  FROM 
    Posts p
  LEFT JOIN 
    Votes v ON p.Id = v.PostId
  GROUP BY 
    p.Id
)
SELECT 
  p.Id,
  p.PostTypeId,
  p.Score,
  p.ViewCount,
  p.LastActivityDate,
  COALESCE(pt.tags, '') AS tags,
  COALESCE(pv.vote_count, 0) AS vote_count,
  COALESCE(pv.upvote_count, 0) AS upvote_count,
  COALESCE(pv.downvote_count, 0) AS downvote_count,
  tsp.score_rank,
  tsp.view_rank,
  tsp2.score_rank AS top_scored_rank,
  tsp2.view_rank AS top_viewed_rank
FROM 
  Posts p
  LEFT JOIN post_tags pt ON p.Id = pt.Id
  LEFT JOIN post_votes pv ON p.Id = pv.Id
  LEFT JOIN top_scored_posts tsp ON p.Id = tsp.Id
  LEFT JOIN top_viewed_posts tsp2 ON p.Id = tsp2.Id
WHERE 
  p.PostTypeId IN (1, 2)
  AND (tsp.score_rank IS NOT NULL OR tsp2.view_rank IS NOT NULL)
ORDER BY 
  p.Score DESC, p.ViewCount DESC;
