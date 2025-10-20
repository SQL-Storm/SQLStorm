-- {"query": "33055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 315} 
SELECT 
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT p.OwnerUserId) AS UniqueAuthors,
    COUNT(DISTINCT c.UserId) AS UniqueCommenters,
    AVG(COALESCE(p.AnswerCount, 0)) AS AvgAnswerCount,
    COUNT(DISTINCT pl.RelatedPostId) AS UniqueLinkedPosts,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END) AS DeletedVotes,
    DATE_TRUNC('month', p.CreationDate) AS PostMonth
FROM 
    Posts p
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    Comments c ON c.PostId = p.Id
LEFT JOIN 
    PostLinks pl ON pl.PostId = p.Id
LEFT JOIN 
    Votes v ON v.PostId = p.Id
WHERE 
    p.CreationDate BETWEEN '2020-01-01' AND '2021-12-31'
GROUP BY 
    p.PostTypeId, PostTypeName, PostMonth
ORDER BY 
    PostMonth DESC, TotalPosts DESC;