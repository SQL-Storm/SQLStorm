-- {"query": "26045.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 456} 
WITH top_users AS (
  SELECT u.Id, u.DisplayName, u.Reputation, COUNT(DISTINCT p.Id) AS post_count
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  GROUP BY u.Id, u.DisplayName, u.Reputation
  ORDER BY post_count DESC
  LIMIT 100
),
top_badges AS (
  SELECT b.UserId, b.Name, b.Class, COUNT(DISTINCT b.Id) AS badge_count
  FROM Badges b
  JOIN top_users tu ON b.UserId = tu.Id
  GROUP BY b.UserId, b.Name, b.Class
  ORDER BY badge_count DESC
  LIMIT 100
),
post_scores AS (
  SELECT p.Id, p.Score, ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS score_rank
  FROM Posts p
  WHERE p.PostTypeId = 1
),
comment_counts AS (
  SELECT p.Id, COUNT(DISTINCT c.Id) AS comment_count
  FROM Posts p
  JOIN Comments c ON p.Id = c.PostId
  GROUP BY p.Id
)
SELECT 
  tu.DisplayName, 
  tu.Reputation, 
  tb.Name AS top_badge, 
  ps.score_rank, 
  cc.comment_count, 
  p.Score AS post_score, 
  p.ViewCount, 
  p.AnswerCount, 
  p.Tags, 
  ph.Comment AS close_reason, 
  ph.UserId AS close_user_id, 
  ph.CreationDate AS close_date, 
  v.VoteTypeId, 
  v.UserId AS vote_user_id, 
  v.CreationDate AS vote_date
FROM top_users tu
JOIN top_badges tb ON tu.Id = tb.UserId
JOIN Posts p ON tu.Id = p.OwnerUserId
JOIN post_scores ps ON p.Id = ps.Id
JOIN comment_counts cc ON p.Id = cc.Id
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2
ORDER BY tu.Reputation DESC, ps.score_rank ASC, cc.comment_count DESC
LIMIT 100;