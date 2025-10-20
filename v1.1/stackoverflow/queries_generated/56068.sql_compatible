WITH top_posts AS (
  SELECT p.Id, p.Score, p.ViewCount, p.Title, p.Tags, p.CreationDate, p.LastActivityDate, 
         p.AcceptedAnswerId, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.OwnerUserId,
         ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS row_num
  FROM Posts p
  JOIN PostTypes pt ON p.PostTypeId = pt.Id
  WHERE pt.Name = 'Question'
    AND p.Score > 0
    AND p.ViewCount > 1000
),
top_users AS (
  SELECT u.Id, u.Reputation, u.DisplayName, u.CreationDate, 
         COUNT(DISTINCT p.Id) AS post_count,
         SUM(p.Score) AS total_score,
         ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS row_num
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate
),
top_badges AS (
  SELECT b.UserId, b.Name, b.Date, b.Class, 
         ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS row_num
  FROM Badges b
)
SELECT tp.Id, tp.Score, tp.ViewCount, tp.Title, tp.Tags, tp.CreationDate, tp.LastActivityDate, 
       tp.AcceptedAnswerId, tp.AnswerCount, tp.CommentCount, tp.FavoriteCount, 
       tu.Id AS user_id, tu.Reputation, tu.DisplayName AS user_display_name, 
       tb.Name AS badge_name, tb.Date AS badge_date, tb.Class AS badge_class
FROM top_posts tp
JOIN top_users tu ON tp.OwnerUserId = tu.Id
JOIN top_badges tb ON tu.Id = tb.UserId
WHERE tp.row_num <= 10 AND tu.row_num <= 10 AND tb.row_num = 1
ORDER BY tp.Score DESC, tu.Reputation DESC;