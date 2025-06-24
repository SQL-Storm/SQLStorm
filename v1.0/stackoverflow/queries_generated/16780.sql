SELECT 
    p.Id AS PostId,
    u.DisplayName AS UserName,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    p.PostTypeId = 1 -- Fetch only questions
ORDER BY 
    p.CreationDate DESC
LIMIT 10; -- Get the latest 10 questions
