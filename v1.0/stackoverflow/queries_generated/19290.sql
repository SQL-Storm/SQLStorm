SELECT 
    u.DisplayName,
    p.Title,
    p.CreationDate,
    p.Score,
    COUNT(c.Id) AS CommentCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Comments c ON p.Id = c.PostId
WHERE 
    p.PostTypeId = 1  -- Selecting only questions
GROUP BY 
    u.DisplayName, p.Title, p.CreationDate, p.Score
ORDER BY 
    p.Score DESC
LIMIT 10;  -- Limit results to the top 10 questions by score
