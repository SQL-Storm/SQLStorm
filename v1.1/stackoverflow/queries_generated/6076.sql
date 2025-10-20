-- {"query": "6076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 303} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostsCreated,
  AVG(CASE WHEN v.VoteTypeId = 2 THEN v.BountyAmount * 0.0 + 1 END) AS AvgUpvotesPerPost, -- placeholder to force calculation path
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
  MAX(p.CreationDate) AS LastPostDate,
  MAX(CASE WHEN b.Id IS NOT NULL THEN b.Date ELSE NULL END) AS LastBadgeDate
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
  AND v.VoteTypeId IN (2,3) -- only up/down votes
LEFT JOIN Badges b ON b.UserId = u.Id
  AND b.Date = (SELECT MAX(Date) FROM Badges b2 WHERE b2.UserId = u.Id)
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  u.Reputation DESC, u.Id
OPTION (MAXDOP 2);