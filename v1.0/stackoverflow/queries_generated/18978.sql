SELECT 
    p.Title, 
    p.CreationDate, 
    u.DisplayName AS Owner, 
    COUNT(a.Id) AS AnswerCount
FROM 
    Posts p
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Posts a ON p.Id = a.ParentId 
WHERE 
    p.PostTypeId = 1 -- Only considering questions
GROUP BY 
    p.Id, u.DisplayName
ORDER BY 
    p.CreationDate DESC;
