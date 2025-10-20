-- {"query": "45091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 208754, "output_tokens": 36873} 
SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS QuestionCount, 
    COUNT(DISTINCT v.Id) AS VoteCount, 
    COUNT(DISTINCT b.Id) AS BadgeCount,
    AVG(p.Score) AS AverageQuestionScore,
    MAX(p.ViewCount) AS MaxViewCount,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY p.CreationDate) AS CreationDateP75,
    RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS QuestionRank
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate > '2015-01-01'
GROUP BY 
    u.Id, u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    QuestionCount DESC, VoteCount DESC
LIMIT 100;