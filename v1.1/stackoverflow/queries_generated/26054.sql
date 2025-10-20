-- {"query": "26054.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 917} 

WITH 
  top_users AS (
    SELECT 
      u.Id, 
      u.DisplayName, 
      COUNT(DISTINCT p.Id) AS num_posts,
      SUM(p.Score) AS total_score
    FROM 
      Users u
    JOIN 
      Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
      u.Id, 
      u.DisplayName
    ORDER BY 
      num_posts DESC, 
      total_score DESC
    LIMIT 100
  ),
  top_tags AS (
    SELECT 
      t.TagName, 
      COUNT(DISTINCT p.Id) AS num_posts,
      SUM(p.Score) AS total_score
    FROM 
      Tags t
    JOIN 
      Posts p ON t.Id = ANY(string_to_array(p.Tags, '><'))
    GROUP BY 
      t.TagName
    ORDER BY 
      num_posts DESC, 
      total_score DESC
    LIMIT 100
  ),
  post_ranks AS (
    SELECT 
      p.Id, 
      p.Score, 
      ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS score_rank,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS type_score_rank
    FROM 
      Posts p
  ),
  user_ranks AS (
    SELECT 
      u.Id, 
      u.Reputation, 
      ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank,
      ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS location_rep_rank
    FROM 
      Users u
  ),
  post_history_stats AS (
    SELECT 
      ph.PostId, 
      COUNT(DISTINCT ph.PostHistoryTypeId) AS num_edits,
      SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS num_closes,
      SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS num_reopens
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
  p.AnswerCount, 
  p.CommentCount, 
  p.ClosedDate, 
  phs.num_edits, 
  phs.num_closes, 
  phs.num_reopens,
  tu.DisplayName AS top_user,
  tt.TagName AS top_tag,
  pr.score_rank,
  pr.type_score_rank,
  ur.rep_rank,
  ur.location_rep_rank,
  CASE 
    WHEN p.Score > 100 THEN 'High'
    WHEN p.Score > 50 THEN 'Medium'
    ELSE 'Low'
  END AS score_category,
  CASE 
    WHEN p.ViewCount > 1000 THEN 'High'
    WHEN p.ViewCount > 500 THEN 'Medium'
    ELSE 'Low'
  END AS view_category,
  p.Tags,
  p.Body,
  p.LastEditDate,
  p.LastActivityDate,
  p.CommunityOwnedDate,
  p.ContentLicense
FROM 
  Posts p
LEFT JOIN 
  post_ranks pr ON p.Id = pr.Id
LEFT JOIN 
  user_ranks ur ON p.OwnerUserId = ur.Id
LEFT JOIN 
  post_history_stats phs ON p.Id = phs.PostId
LEFT JOIN 
  top_users tu ON p.OwnerUserId = tu.Id
LEFT JOIN 
  top_tags tt ON tt.TagName = ANY(string_to_array(p.Tags, '><'))
WHERE 
  p.Score > 50 
  AND p.ViewCount > 100 
  AND p.AnswerCount > 5 
  AND p.CommentCount > 10 
  AND p.ClosedDate IS NULL 
  AND phs.num_edits > 5 
  AND phs.num_closes = 0 
  AND phs.num_reopens = 0 
  AND tu.num_posts > 100 
  AND tu.total_score > 1000 
  AND tt.num_posts > 100 
  AND tt.total_score > 1000 
  AND pr.score_rank < 1000 
  AND pr.type_score_rank < 100 
  AND ur.rep_rank < 1000 
  AND ur.location_rep_rank < 100
ORDER BY 
  p.Score DESC, 
  p.ViewCount DESC, 
  p.AnswerCount DESC, 
  p.CommentCount DESC;
