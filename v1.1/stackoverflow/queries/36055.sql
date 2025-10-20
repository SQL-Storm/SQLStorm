-- {"query": "36055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 234} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  SUM(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) AS BadgesEarned,
  AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgPostScore,
  MAX(p.CreationDate) AS LastPostDate
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,3)
  LEFT JOIN Badges b ON b.UserId = u.Id
GROUP BY
  u.Id, u.DisplayName, u.Reputation
ORDER BY
  Reputation DESC, LastPostDate DESC
LIMIT 100;