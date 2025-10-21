-- {"query": "36086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 252} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostsCreated,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
  SUM(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) AS BadgesEarned,
  MAX(p.CreationDate) AS LastActiveDate
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.UserId = u.Id AND v.PostId = p.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN Posts p2 ON p2.OwnerUserId = u.Id AND p2.Id = p.Id
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  LastActiveDate DESC
LIMIT 100;