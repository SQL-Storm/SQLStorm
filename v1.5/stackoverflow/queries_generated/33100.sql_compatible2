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
    COUNT(DISTINCT PL.RelatedPostId) AS UniqueRelatedPosts,
    STRING_AGG(DISTINCT LT.Name, ', ') AS DistinctLinkTypes,
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
    PostLinks PL ON PL.PostId = p.Id
LEFT JOIN 
    LinkTypes LT ON PL.LinkTypeId = LT.Id
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Badges b ON b.UserId = u.Id
LEFT JOIN 
    PostLinks PL2 ON PL2.PostId = p.Id OR PL2.RelatedPostId = p.Id
LEFT JOIN 
    LinkTypes LT2 ON PL2.LinkTypeId = LT2.Id
WHERE 
    p.CreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
GROUP BY 
    p.PostTypeId, pt.Name
ORDER BY 
    TotalPosts DESC
LIMIT 100;