-- {"query": "44085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 317}

WITH cte AS (
  SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Tags,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
)
SELECT 
  DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT cte.OwnerUserId)) AS user_rank,
  COUNT(DISTINCT cte.OwnerUserId) AS unique_users,
  SUM(cte.Score) AS total_score,
  SUM(cte.ViewCount) AS total_views,
  SUM(cte.AnswerCount) AS total_answers,
  SUM(cte.CommentCount) AS total_comments,
  SUM(cte.FavoriteCount) AS total_favorites,
  COUNT(DISTINCT cte.Tags) AS unique_tags
FROM cte
WHERE cte.rn = 1
GROUP BY CUBE (user_rank)
ORDER BY user_rank;
