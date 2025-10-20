-- {"query": "44004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 9176, "output_tokens": 3289} 

WITH cte AS (
  SELECT p.Id AS PostId, 
         p.PostTypeId, 
         p.CreationDate, 
         p.OwnerUserId, 
         p.Score, 
         p.AnswerCount, 
         p.CommentCount,
         p.FavoriteCount,
         COALESCE(p.ClosedDate, CAST('9999-12-31' AS TIMESTAMP)) AS ClosedDate,
         COALESCE(p.CommunityOwnedDate, CAST('9999-12-31' AS TIMESTAMP)) AS CommunityOwnedDate,
         CASE WHEN p.PostTypeId = 2 THEN p.ParentId ELSE p.Id END AS ParentId,
         ROW_NUMBER() OVER (PARTITION BY CASE WHEN p.PostTypeId = 2 THEN p.ParentId ELSE p.Id END ORDER BY p.CreationDate) AS rn
  FROM Posts p
),
all_posts AS (
  SELECT PostId, 
         PostTypeId, 
         CreationDate, 
         OwnerUserId, 
         Score, 
         AnswerCount, 
         CommentCount, 
         FavoriteCount, 
         ClosedDate, 
         CommunityOwnedDate,
         ParentId,
         rn
  FROM cte
  WHERE rn = 1
),
questions AS (
  SELECT * 
  FROM all_posts
  WHERE PostTypeId = 1
),
answers AS (
  SELECT * 
  FROM all_posts
  WHERE PostTypeId = 2
),
q_activity AS (
  SELECT q.PostId AS QuestionId,
         q.CreationDate AS QuestionCreatedDate,
         q.OwnerUserId AS QuestionOwnerUserId,
         q.Score AS QuestionScore,
         q.AnswerCount AS QuestionAnswerCount, 
         q.CommentCount AS QuestionCommentCount,
         q.FavoriteCount AS QuestionFavoriteCount,
         q.ClosedDate AS QuestionClosedDate,
         q.CommunityOwnedDate AS QuestionCommunityOwnedDate,
         a.PostId AS AnswerId,
         a.CreationDate AS AnswerCreatedDate,
         a.OwnerUserId AS AnswerOwnerUserId,
         a.Score AS AnswerScore,
         a.CommentCount AS AnswerCommentCount
  FROM questions q
  LEFT JOIN answers a ON q.PostId = a.ParentId
)
SELECT q.QuestionId,
       q.QuestionCreatedDate,
       q.QuestionOwnerUserId,
       q.QuestionScore,
       q.QuestionAnswerCount,
       q.QuestionCommentCount,
       q.QuestionFavoriteCount,
       q.QuestionClosedDate,
       q.QuestionCommunityOwnedDate,
       q.AnswerId,
       q.AnswerCreatedDate,
       q.AnswerOwnerUserId,
       q.AnswerScore,
       q.AnswerCommentCount
FROM q_activity q
ORDER BY q.QuestionCreatedDate DESC, q.AnswerCreatedDate DESC;
