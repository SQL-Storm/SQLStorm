SELECT 
    u.DisplayName AS UserName,
    q.Title AS QuestionTitle,
    q.CreationDate AS QuestionCreationDate,
    q.ViewCount AS QuestionViews,
    a.CreationDate AS AnswerCreationDate,
    a.Score AS AnswerScore,
    a.Body AS AnswerBody,
    u.UpVotes AS AnswerUpVotes,
    u.DownVotes AS AnswerDownVotes
FROM 
    Posts q
INNER JOIN 
    Posts a ON q.Id = a.ParentId
INNER JOIN 
    Users u ON q.OwnerUserId = u.Id
WHERE 
    q.PostTypeId = 1
    AND a.PostTypeId = 2
    AND q.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
GROUP BY
    u.DisplayName,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    a.CreationDate,
    a.Score,
    a.Body,
    u.UpVotes,
    u.DownVotes,
    q.Id,
    a.Id,
    u.Id
ORDER BY 
    q.ViewCount DESC, 
    a.Score DESC
LIMIT 100;