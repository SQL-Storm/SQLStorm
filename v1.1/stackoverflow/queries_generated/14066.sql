-- {"query": "14066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 156445, "output_tokens": 67198} 

WITH cte AS (
  SELECT p.Id, p.PostTypeId, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, u.Reputation, u.CreationDate AS UserCreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, b.Name AS BadgeName, b.Date AS BadgeDate, b.Class AS BadgeClass, b.TagBased AS BadgeTagBased
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
  WHERE p.PostTypeId IN (1, 2)
),
dup_posts AS (
  SELECT p.Id, p.ParentId, p.CreationDate, p.AnswerCount, p.Score, p.ViewCount, p.FavoriteCount, p.CommentCount, p.OwnerUserId
  FROM Posts p
  INNER JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3
),
top_answers AS (
  SELECT p.Id, p.ParentId, p.CreationDate, p.AnswerCount, p.Score, p.ViewCount, p.FavoriteCount, p.CommentCount, p.OwnerUserId, 
    ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 2
)
SELECT 
  cte.Id, 
  cte.PostTypeId, 
  cte.CreationDate, 
  cte.OwnerUserId, 
  cte.Score, 
  cte.ViewCount, 
  cte.AnswerCount, 
  cte.CommentCount, 
  cte.FavoriteCount, 
  cte.Reputation, 
  cte.UserCreationDate, 
  cte.LastAccessDate, 
  cte.Views, 
  cte.UpVotes, 
  cte.DownVotes, 
  cte.BadgeName, 
  cte.BadgeDate, 
  cte.BadgeClass, 
  cte.BadgeTagBased,
  CASE WHEN dup_posts.Id IS NOT NULL THEN 'Duplicate' ELSE 'Not Duplicate' END AS IsDuplicate,
  CASE WHEN top_answers.rn = 1 THEN 'Top Answer' ELSE 'Not Top Answer' END AS IsTopAnswer
FROM cte
LEFT JOIN dup_posts ON cte.Id = dup_posts.Id
LEFT JOIN top_answers ON cte.Id = top_answers.ParentId
ORDER BY cte.CreationDate DESC;
