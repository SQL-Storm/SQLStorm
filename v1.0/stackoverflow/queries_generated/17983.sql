SELECT 
    U.DisplayName AS User,
    P.Title AS PostTitle,
    P.CreationDate,
    P.Score,
    C.Text AS CommentText
FROM 
    Posts P
JOIN 
    Users U ON P.OwnerUserId = U.Id
LEFT JOIN 
    Comments C ON P.Id = C.PostId
WHERE 
    P.PostTypeId = 1  -- Filter for questions
ORDER BY 
    P.CreationDate DESC
LIMIT 10;  -- Limit to the most recent 10 questions
