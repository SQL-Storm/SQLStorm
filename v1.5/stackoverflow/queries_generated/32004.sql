-- {"query": "32004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 314} 

SELECT 
    u.DisplayName AS UserName,
    u.Reputation,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
    SUM(CASE WHEN pt.Id = 1 THEN 1 ELSE 0 END) AS QuestionsPosted,
    SUM(CASE WHEN pt.Id = 2 THEN 1 ELSE 0 END) AS AnswersPosted,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(b.Id) AS TotalBadges,
    AVG(p.Score) AS AveragePostScore,
    MAX(p.Score) AS HighestPostScore,
    MIN(p.Score) AS LowestPostScore
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    u.Reputation > 1000 AND p.CreationDate > '2020-01-01'
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    Reputation DESC, UpVotesReceived DESC, UserName ASC;
