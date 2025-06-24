SELECT 
    p.Title, 
    p.CreationDate, 
    u.DisplayName AS OwnerDisplayName, 
    COALESCE(p.AnswerCount, 0) AS AnswerCount, 
    COALESCE(p.ViewCount, 0) AS ViewCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    p.PostTypeId = 1 -- Filter for Questions
ORDER BY 
    p.CreationDate DESC
LIMIT 10; -- Limit to the most recent 10 questions
