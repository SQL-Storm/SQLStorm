-- {"query": "36037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 279} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostsCreated,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
  SUM(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) AS BadgesEarned,
  COUNT(DISTINCT c.Id) AS CommentsWritten,
  MAX(p.CreationDate) AS LastActivityDate
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
WHERE
  u.Id IN (SELECT DISTINCT OwnerUserId FROM Posts WHERE OwnerUserId IS NOT NULL)
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  AVG(p.Score) DESC, u.Reputation DESC
LIMIT 100;