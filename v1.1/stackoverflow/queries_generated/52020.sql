-- {"query": "52020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 262} 
SELECT u.Id, u.DisplayName, u.Reputation,
       COUNT(DISTINCT p.Id) AS TotalAnswers,
       AVG(v.Score) AS AvgScorePerAnswer,
       SUM(v.Score) AS TotalScoreFromAnswers,
       COUNT(DISTINCT b.Id) AS BadgeCount,
       MAX(p.CreationDate) AS LastAnswerDate
FROM Users u
INNER JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 2
LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (1, 2, 3)
INNER JOIN Badges b ON u.Id = b.UserId
WHERE u.CreationDate >= '2010-01-01'
  AND p.Score > 0
  AND p.ParentId IS NOT NULL
  AND p.ParentId IN (
      SELECT Id FROM Posts WHERE PostTypeId = 1 AND ViewCount > 1000
  )
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 100
   AND COUNT(DISTINCT b.Id) >= 10
   AND AVG(v.Score) > 10
ORDER BY TotalScoreFromAnswers DESC, AvgScorePerAnswer DESC
LIMIT 50;