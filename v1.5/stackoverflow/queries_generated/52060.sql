-- {"query": "52060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 207} 
SELECT t.TagName, 
       AVG(p.AnswerCount) AS AvgAnswerCount,
       COUNT(DISTINCT p.Id) AS QuestionCount,
       SUM(p.Score) AS TotalScore,
       MAX(u.Reputation) AS MaxUserReputation
FROM Tags t
JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
JOIN Users u ON u.Id = p.OwnerUserId
JOIN Votes v ON v.PostId = p.Id
JOIN PostHistory ph ON ph.PostId = p.Id
JOIN Comments c ON c.PostId = p.Id
WHERE p.PostTypeId = 1
  AND p.AcceptedAnswerId IS NOT NULL
  AND ph.PostHistoryTypeId IN (10, 11)
  AND v.VoteTypeId = 2
  AND YEAR(p.CreationDate) = 2023
GROUP BY t.TagName
HAVING COUNT(DISTINCT p.Id) > 10
ORDER BY AvgAnswerCount DESC, TotalScore DESC
LIMIT 20;