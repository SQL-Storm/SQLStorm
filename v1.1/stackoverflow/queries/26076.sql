-- {"query": "26076.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 730} 
WITH top_10_users AS (
  SELECT u.Id, u.DisplayName, COUNT(p.Id) AS post_count
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1 AND p.Score > 10
  GROUP BY u.Id, u.DisplayName
  ORDER BY post_count DESC
  LIMIT 10
),
user_badges AS (
  SELECT u.Id, COUNT(b.Id) AS badge_count
  FROM Users u
  JOIN Badges b ON u.Id = b.UserId
  WHERE b.Class = 1
  GROUP BY u.Id
),
question_answers AS (
  SELECT p.Id, COUNT(a.Id) AS answer_count
  FROM Posts p
  JOIN Posts a ON p.Id = a.ParentId
  WHERE p.PostTypeId = 1 AND a.PostTypeId = 2
  GROUP BY p.Id
),
top_10_tags AS (
  SELECT T.TagName, COUNT(p.Id) AS post_count
  FROM Tags T
  JOIN Posts p ON T.Id = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY T.TagName
  ORDER BY post_count DESC
  LIMIT 10
)
SELECT 
  p.Id,
  p.Title,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  u.DisplayName AS owner_display_name,
  u.Reputation AS owner_reputation,
  ub.badge_count,
  COALESCE(qa.answer_count, 0) AS answer_count,
  t.TagName,
  ph.PostHistoryTypeId,
  ph.CreationDate AS post_history_date,
  v.VoteTypeId,
  v.CreationDate AS vote_date,
  b.Name AS badge_name,
  b.Date AS badge_date,
  CASE 
    WHEN p.Score > 10 THEN 'High Score'
    WHEN p.Score < -10 THEN 'Low Score'
    ELSE 'Normal Score'
  END AS score_category,
  CASE 
    WHEN u.Reputation > 10000 THEN 'High Reputation'
    WHEN u.Reputation < 100 THEN 'Low Reputation'
    ELSE 'Normal Reputation'
  END AS reputation_category,
  ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate) AS row_num,
  LAG(ph.CreationDate) OVER (PARTITION BY p.Id ORDER BY ph.CreationDate) AS prev_post_history_date,
  LEAD(v.CreationDate) OVER (PARTITION BY p.Id ORDER BY v.CreationDate) AS next_vote_date
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN user_badges ub ON u.Id = ub.Id
LEFT JOIN question_answers qa ON p.Id = qa.Id
LEFT JOIN Tags t ON p.Id = t.Id
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE p.PostTypeId = 1
AND p.Score > 0
AND u.Reputation > 100
AND ph.PostHistoryTypeId IN (10, 11, 12, 13)
AND v.VoteTypeId IN (2, 3)
AND b.Class = 1
AND t.TagName IN (SELECT TagName FROM top_10_tags)
AND u.Id IN (SELECT Id FROM top_10_users)
ORDER BY p.Score DESC, p.ViewCount DESC, p.AnswerCount DESC;