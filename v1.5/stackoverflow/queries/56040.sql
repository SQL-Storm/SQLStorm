WITH top_10_users_with_most_upvotes AS (
  SELECT u.Id, u.DisplayName, COUNT(v.Id) AS total_upvotes
  FROM Users u
  JOIN Votes v ON u.Id = v.UserId
  WHERE v.VoteTypeId = 2
  GROUP BY u.Id, u.DisplayName
  ORDER BY total_upvotes DESC
  LIMIT 10
),
top_10_posts_with_most_comments AS (
  SELECT p.Id, p.Title, COUNT(c.Id) AS total_comments
  FROM Posts p
  JOIN Comments c ON p.Id = c.PostId
  GROUP BY p.Id, p.Title
  ORDER BY total_comments DESC
  LIMIT 10
),
top_10_tags_with_most_questions AS (
  SELECT t.TagName, COUNT(p.Id) AS total_questions
  FROM Tags t
  JOIN Posts p ON POSITION(t.TagName IN COALESCE(p.Tags, '')) > 0
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
  ORDER BY total_questions DESC
  LIMIT 10
)
SELECT
  u.Id,
  u.DisplayName,
  u.Reputation,
  COUNT(v.Id) AS total_votes,
  COUNT(DISTINCT p.Id) AS total_posts,
  COUNT(DISTINCT c.Id) AS total_comments,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS total_upvotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS total_downvotes,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS total_questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS total_answers,
  SUM(CASE WHEN p.PostTypeId = 3 THEN 1 ELSE 0 END) AS total_wiki,
  COUNT(DISTINCT t.TagName) AS total_tags
FROM Users u
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Tags t ON t.TagName IN (SELECT TagName FROM top_10_tags_with_most_questions)
WHERE u.Reputation > 1000
  AND u.Id IN (SELECT Id FROM top_10_users_with_most_upvotes)
  AND p.Id IN (SELECT Id FROM top_10_posts_with_most_comments)
  AND t.TagName IN (SELECT TagName FROM top_10_tags_with_most_questions)
GROUP BY u.Id, u.DisplayName, u.Reputation
ORDER BY total_votes DESC, total_posts DESC, total_comments DESC;