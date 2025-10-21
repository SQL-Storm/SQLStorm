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
  AND CAST(p.CreationDate AS DATE) >= DATE '2023-01-01'
  AND CAST(p.CreationDate AS DATE) < DATE '2024-01-01'
GROUP BY t.TagName
HAVING COUNT(DISTINCT p.Id) > 10
ORDER BY AvgAnswerCount DESC, TotalScore DESC
LIMIT 20;