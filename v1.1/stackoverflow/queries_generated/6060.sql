-- {"query": "6060.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 368} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  COUNT(DISTINCT p.Id) AS PostsCreated,
  SUM(COALESCE(p.Score,0)) AS TotalPostScore,
  SUM(COALESCE(v.BountyAmount,0)) AS TotalBountiesEarned,
  AVG(COALESCE(u.Reputation,0)) AS AvgReputation,
  MAX(p.LastActivityDate) AS LastActivePostDate,
  COUNT(DISTINCT bl.Id) AS BadgesEarned,
  STRING_AGG(DISTINCT t.Name, ',') AS TagBasedBadges
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,6,8,9,10,11,12,14,15,16)
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN Badges bl ON bl.UserId = u.Id
LEFT JOIN (SELECT Id, UserId, Name FROM Badges WHERE TagBased = 1) t ON t.UserId = u.Id
WHERE
  u.CreationDate >= TIMESTAMP '2015-01-01 00:00:00'
  AND u.LastAccessDate >= TIMESTAMP '2020-01-01 00:00:00'
  AND (p.Id IS NULL OR p.PostTypeId IN (1,2))
GROUP BY u.Id, u.DisplayName
HAVING
  COUNT(DISTINCT p.Id) > 5
  AND SUM(COALESCE(v.BountyAmount,0)) > 0
ORDER BY TotalPostScore DESC, PostsCreated DESC
LIMIT 100;