-- {"query": "33059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 276} 
SELECT 
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    SUM(CASE WHEN p.ViewCount > 1000 THEN 1 ELSE 0 END) AS PostsWithHighViews,
    COUNT(DISTINCT p.OwnerUserId) AS UniqueAuthors,
    COUNT(DISTINCT c.UserId) AS CommentingUsers,
    AVG(c.Score) AS AverageCommentScore,
    COUNT(DISTINCT v.UserId) AS VotingUsers,
    SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) AS TotalVotes,
    DATE_TRUNC('month', p.CreationDate) AS MonthOfCreation
FROM 
    Posts p
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    Comments c ON c.PostId = p.Id
LEFT JOIN 
    Votes v ON v.PostId = p.Id
WHERE 
    p.CreationDate >= DATE '2020-01-01' AND p.CreationDate < DATE '2022-01-01'
GROUP BY 
    p.PostTypeId, pt.Name, DATE_TRUNC('month', p.CreationDate)
ORDER BY 
    MonthOfCreation DESC, TotalPosts DESC;