-- {"query": "36022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 264} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostsCreated,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast,
  SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotesCast,
  COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.Id END) AS BadgesEarned,
  MAX(p.CreationDate) AS LastPostDate,
  MAX(v.CreationDate) AS LastVoteDate
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.UserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
WHERE
  u.AccountId IS NOT NULL
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  Reputation DESC, LastPostDate DESC
LIMIT 100;