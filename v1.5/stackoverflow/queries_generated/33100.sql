-- {"query": "33100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 398} 
SELECT 
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT p.OwnerUserId) AS UniqueUsers,
    COUNT(c.Id) AS TotalComments,
    AVG(c.Score) AS AverageCommentScore,
    COUNT(DISTINCT v.UserId) AS UniqueVoters,
    COUNT(DISTINCT pl.RelatedPostId) AS UniqueRelatedPosts,
    STRING_AGG(DISTINCT tt.Name, ', ') AS DistinctLinkTypes,
    COUNT(DISTINCT b.UserId) AS UniqueBadgeHolders,
    COUNT(DISTINCT u.Id) AS ActiveUsers,
    MIN(p.CreationDate) AS EarliestPostDate,
    MAX(p.LastActivityDate) AS LatestActivityDate
FROM 
    Posts p
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    Comments c ON c.PostId = p.Id
LEFT JOIN 
    Votes v ON v.PostId = p.Id
LEFT JOIN 
    PostLinks pl ON pl.PostId = p.Id
LEFT JOIN 
    LinkTypes lt ON pl.LinkTypeId = lt.Id
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Badges b ON b.UserId = u.Id
LEFT JOIN 
    Users u2 ON b.UserId = u2.Id
LEFT JOIN 
    PostLinks pl2 ON pl2.PostId = p.Id OR pl2.RelatedPostId = p.Id
LEFT JOIN 
    LinkTypes lt2 ON pl2.LinkTypeId = lt2.Id
WHERE 
    p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
GROUP BY 
    p.PostTypeId, pt.Name
ORDER BY 
    TotalPosts DESC
LIMIT 100;