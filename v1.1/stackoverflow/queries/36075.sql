-- {"query": "36075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 265} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  COUNT(DISTINCT p.Id) AS PostsCreated,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast,
  SUM(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) AS BadgesEarned,
  MAX(p.LastActivityDate) FILTER (WHERE p.PostTypeId = 1) AS LastQuestionActivity,
  AVG(p.Score) AS AvgPostScore
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
WHERE
  u.AccountId IS NOT NULL
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
ORDER BY
  Reputation DESC, LastQuestionActivity DESC
LIMIT 100;