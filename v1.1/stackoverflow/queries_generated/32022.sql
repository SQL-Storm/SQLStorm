-- {"query": "32022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 175} 

SELECT 
    u.DisplayName AS UserName,
    p.Title AS QuestionTitle,
    p.CreationDate AS QuestionCreationDate,
    p.ViewCount AS QuestionViews,
    a.CreationDate AS AnswerCreationDate,
    a.Score AS AnswerScore,
    a.Body AS AnswerBody,
    a.UpVotes AS AnswerUpVotes,
    a.DownVotes AS AnswerDownVotes
FROM 
    Posts q
INNER JOIN 
    Posts a ON q.Id = a.ParentId
INNER JOIN 
    Users u ON q.OwnerUserId = u.Id
WHERE 
    q.PostTypeId = 1
    AND a.PostTypeId = 2
    AND q.CreationDate > NOW() - INTERVAL '1 year'
ORDER BY 
    q.ViewCount DESC, 
    a.Score DESC
LIMIT 100;
