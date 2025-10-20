-- {"query": "45100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 229400, "output_tokens": 40564} 
SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS QuestionCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    AVG(p.Score) AS AverageQuestionScore,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
    (SELECT MAX(CreationDate) FROM Posts WHERE OwnerUserId = u.Id) AS MostRecentPostDate
FROM 
    Users u
JOIN 
    Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN 
    Votes v ON v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
LEFT JOIN 
    Badges b ON b.UserId = u.Id
WHERE 
    u.Reputation > 1000
    AND p.CreationDate > '2018-01-01'
GROUP BY 
    u.Id, u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    AverageQuestionScore DESC, VoteCount DESC
LIMIT 100;