-- {"query": "26062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 738} 

WITH top_users AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
  FROM 
    Users u
  LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN 
    Votes v ON p.Id = v.PostId
  GROUP BY 
    u.Id, u.DisplayName
  HAVING 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 1000
),
top_posts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS score_rank,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS view_rank
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1
),
user_badges AS (
  SELECT 
    u.Id, 
    COUNT(b.Id) AS badge_count
  FROM 
    Users u
  LEFT JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    u.Id
)
SELECT 
  u.Id, 
  u.DisplayName, 
  u.Reputation, 
  tu.upvotes, 
  tu.downvotes, 
  ub.badge_count,
  COALESCE(p.Score, 0) AS post_score,
  COALESCE(p.ViewCount, 0) AS post_views,
  COALESCE(p.AnswerCount, 0) AS post_answers,
  COALESCE(p.CommentCount, 0) AS post_comments,
  COALESCE(p.FavoriteCount, 0) AS post_favorites,
  p.score_rank,
  p.view_rank,
  SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS closed_count,
  SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS reopened_count,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS post_upvotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS post_downvotes,
  STRING_AGG(DISTINCT t.TagName, ', ') AS tags
FROM 
  Users u
LEFT JOIN 
  top_users tu ON u.Id = tu.Id
LEFT JOIN 
  user_badges ub ON u.Id = ub.Id
LEFT JOIN 
  Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN 
  top_posts tp ON p.Id = tp.Id
LEFT JOIN 
  PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
  Votes v ON p.Id = v.PostId
LEFT JOIN 
  PostTags pt ON p.Id = pt.PostId
LEFT JOIN 
  Tags t ON pt.TagId = t.Id
GROUP BY 
  u.Id, u.DisplayName, u.Reputation, tu.upvotes, tu.downvotes, ub.badge_count, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.score_rank, p.view_rank
ORDER BY 
  u.Reputation DESC, tu.upvotes DESC, ub.badge_count DESC;
