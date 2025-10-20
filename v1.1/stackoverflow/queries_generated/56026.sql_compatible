WITH top_100_users AS (
  SELECT Id, Reputation, DisplayName
  FROM Users
  ORDER BY Reputation DESC
  LIMIT 100
),
top_100_posts AS (
  SELECT Id, PostTypeId, Score, ViewCount, AnswerCount, OwnerUserId
  FROM Posts
  WHERE OwnerUserId IN (SELECT Id FROM top_100_users)
  ORDER BY Score DESC
  LIMIT 100
),
top_100_comments AS (
  SELECT Id, PostId, Score, Text
  FROM Comments
  WHERE PostId IN (SELECT Id FROM top_100_posts)
  ORDER BY Score DESC
  LIMIT 100
),
top_100_votes AS (
  SELECT Id, PostId, VoteTypeId
  FROM Votes
  WHERE PostId IN (SELECT Id FROM top_100_posts)
  ORDER BY VoteTypeId DESC
  LIMIT 100
),
top_100_post_history AS (
  SELECT Id, PostId, PostHistoryTypeId
  FROM PostHistory
  WHERE PostId IN (SELECT Id FROM top_100_posts)
  ORDER BY PostHistoryTypeId DESC
  LIMIT 100
),
top_100_badges AS (
  SELECT Id, UserId, Name
  FROM Badges
  WHERE UserId IN (SELECT Id FROM top_100_users)
  ORDER BY Name DESC
  LIMIT 100
)
SELECT 
  u.Id AS user_id,
  u.DisplayName AS user_display_name,
  p.Id AS post_id,
  p.PostTypeId AS post_type_id,
  p.Score AS post_score,
  p.ViewCount AS post_view_count,
  p.AnswerCount AS post_answer_count,
  c.Id AS comment_id,
  c.Score AS comment_score,
  c.Text AS comment_text,
  v.Id AS vote_id,
  v.VoteTypeId AS vote_type_id,
  ph.Id AS post_history_id,
  ph.PostHistoryTypeId AS post_history_type_id,
  b.Id AS badge_id,
  b.Name AS badge_name,
  u.Reputation,
  p.OwnerUserId
FROM top_100_users u
JOIN top_100_posts p ON u.Id = p.OwnerUserId
JOIN top_100_comments c ON p.Id = c.PostId
JOIN top_100_votes v ON p.Id = v.PostId
JOIN top_100_post_history ph ON p.Id = ph.PostId
JOIN top_100_badges b ON u.Id = b.UserId
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  p.Id,
  p.PostTypeId,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.OwnerUserId,
  c.Id,
  c.Score,
  c.Text,
  v.Id,
  v.VoteTypeId,
  ph.Id,
  ph.PostHistoryTypeId,
  b.Id,
  b.Name
ORDER BY u.Reputation DESC, p.Score DESC, c.Score DESC, v.VoteTypeId DESC, ph.PostHistoryTypeId DESC, b.Name DESC;