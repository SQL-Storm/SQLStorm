SELECT
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
LEFT JOIN Votes v ON p.Id = v.PostId
WHERE u.Location IS NOT NULL
GROUP BY u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 10
ORDER BY SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) DESC;