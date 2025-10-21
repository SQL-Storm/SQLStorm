-- {"query": "33099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 236} 
SELECT 
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AvgScore,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveVotes,
    SUM(CASE WHEN p.Score < 0 THEN 1 ELSE 0 END) AS NegativeVotes,
    COUNT(DISTINCT u.Id) AS UniqueUsers,
    COUNT(c.Id) AS TotalComments,
    AVG(c.Score) AS AvgCommentScore,
    COUNT(DISTINCT v.UserId) AS DistinctVoters,
    MIN(p.CreationDate) AS EarliestPost,
    MAX(p.LastActivityDate) AS MostRecentActivity
FROM 
    Posts p
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Comments c ON c.PostId = p.Id
LEFT JOIN 
    Votes v ON v.PostId = p.Id
GROUP BY 
    p.PostTypeId,
    pt.Name
ORDER BY 
    TotalPosts DESC
LIMIT 10;