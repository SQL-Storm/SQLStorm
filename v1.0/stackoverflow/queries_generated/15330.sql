SELECT 
    u.DisplayName, 
    u.Reputation, 
    COUNT(p.Id) AS PostCount, 
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount, 
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount 
FROM 
    Users u 
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId 
GROUP BY 
    u.Id 
ORDER BY 
    u.Reputation DESC 
LIMIT 10;
