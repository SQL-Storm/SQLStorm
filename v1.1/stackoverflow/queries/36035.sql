-- {"query": "36035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 330} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  COUNT(DISTINCT p.Id) AS PostsCreated,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCreated,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCreated,
  AVG(p.Score) AS AveragePostScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast,
  COUNT(DISTINCT c.Id) AS CommentsMade,
  SUM(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) AS BadgesEarned,
  MAX(p.LastActivityDate) AS LastActiveDate
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
LEFT JOIN Comments c ON c.UserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  Reputation DESC, u.CreationDate ASC
LIMIT 100;