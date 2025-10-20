WITH recent_posts AS (
  SELECT p.Id, p.CreationDate, p.Score, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate, u.Reputation, u.Views, u.UpVotes, u.DownVotes
  FROM Posts p
  INNER JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
  ORDER BY p.CreationDate DESC
  FETCH FIRST 1000000 ROWS ONLY
),
active_users AS (
  SELECT u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes, COUNT(p.Id) AS post_count
  FROM Users u
  INNER JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
  GROUP BY u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes
  ORDER BY post_count DESC
  FETCH FIRST 100000 ROWS ONLY
),
top_tags AS (
  SELECT t.TagName, t.Count
  FROM Tags t
  ORDER BY t.Count DESC
  FETCH FIRST 1000 ROWS ONLY
),
top_badges AS (
  SELECT b.Name, b.Class, COUNT(*) AS badge_count
  FROM Badges b
  GROUP BY b.Name, b.Class
  ORDER BY badge_count DESC
  FETCH FIRST 10000 ROWS ONLY
),
top_comments AS (
  SELECT c.Id, c.PostId, c.Score, c.CreationDate, u.Reputation, u.Views, u.UpVotes, u.DownVotes
  FROM Comments c
  INNER JOIN Users u ON c.UserId = u.Id
  ORDER BY c.Score DESC
  FETCH FIRST 1000000 ROWS ONLY
),
top_votes AS (
  SELECT v.Id, v.PostId, v.VoteTypeId, v.CreationDate, u.Reputation, u.Views, u.UpVotes, u.DownVotes
  FROM Votes v
  INNER JOIN Users u ON v.UserId = u.Id
  ORDER BY v.CreationDate DESC
  FETCH FIRST 1000000 ROWS ONLY
),
top_links AS (
  SELECT l.Id, l.PostId, l.RelatedPostId, l.LinkTypeId, p1.CreationDate AS post1_date, p2.CreationDate AS post2_date
  FROM PostLinks l
  INNER JOIN Posts p1 ON l.PostId = p1.Id
  INNER JOIN Posts p2 ON l.RelatedPostId = p2.Id
  ORDER BY l.CreationDate DESC
  FETCH FIRST 1000000 ROWS ONLY
)
SELECT
  (SELECT COUNT(*) FROM recent_posts) AS recent_posts_count,
  (SELECT COUNT(*) FROM active_users) AS active_users_count,
  (SELECT COUNT(*) FROM top_tags) AS top_tags_count,
  (SELECT COUNT(*) FROM top_badges) AS top_badges_count,
  (SELECT COUNT(*) FROM top_comments) AS top_comments_count,
  (SELECT COUNT(*) FROM top_votes) AS top_votes_count,
  (SELECT COUNT(*) FROM top_links) AS top_links_count;