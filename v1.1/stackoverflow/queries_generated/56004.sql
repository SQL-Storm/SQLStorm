-- {"query": "56004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 299} 

SELECT 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS TotalPosts, 
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScorePosts, 
    SUM(CASE WHEN p.Score < 0 THEN 1 ELSE 0 END) AS NegativeScorePosts, 
    AVG(p.Score) AS AveragePostScore, 
    COUNT(DISTINCT ph.PostHistoryTypeId) AS PostHistoryTypesCount, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCount, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCount, 
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount, 
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId
JOIN 
    PostHistory ph ON p.Id = ph.PostId
JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 1000 AND p.CreationDate > '2010-01-01' AND p.CreationDate < '2020-01-01'
GROUP BY 
    u.DisplayName
ORDER BY 
    TotalPosts DESC;
