-- {"query": "52032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 313} 
SELECT u.Id, u.DisplayName, u.Reputation, 
       COUNT(DISTINCT p.Id) AS PostCount,
       SUM(p.Score) AS TotalPostScore,
       AVG(p.Score) AS AvgPostScore,
       COUNT(DISTINCT v.Id) AS TotalVotes,
       COUNT(DISTINCT c.Id) AS CommentCount,
       COUNT(DISTINCT b.Id) AS BadgeCount,
       SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND pa.OwnerUserId = u.Id THEN 1 ELSE 0 END) AS AcceptedAnswers
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class <= 2
LEFT JOIN Posts pa ON pa.Id = p.AcceptedAnswerId AND pa.PostTypeId = 2
WHERE u.Reputation > 1000
  AND u.CreationDate < '2023-01-01'
  AND p.ViewCount > 500
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 10
   AND AVG(p.Score) > 5
   AND COUNT(DISTINCT b.Id) > 2
ORDER BY TotalPostScore DESC, BadgeCount DESC
LIMIT 20;