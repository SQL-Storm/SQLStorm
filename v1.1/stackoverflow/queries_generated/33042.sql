-- {"query": "33042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 278} 
SELECT 
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(p.Id) AS TotalPosts,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionsCount,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswersCount,
    AVG(p.Score) AS AveragePostScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
    COUNT(CASE WHEN c.Id IS NOT NULL THEN 1 END) AS CommentCount,
    MAX(p.CreationDate) AS LastPostDate
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2
LEFT JOIN 
    Comments c ON p.Id = c.PostId
WHERE 
    u.Reputation >= 1000
    AND p.CreationDate > NOW() - INTERVAL '1 year'
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
ORDER BY 
    TotalPosts DESC, UpVotesReceived DESC
LIMIT 100;