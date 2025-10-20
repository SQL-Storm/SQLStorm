SELECT 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT u.Id) AS TotalUsers,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(u.Reputation) AS MaxReputation,
    MIN(p.CreationDate) AS EarliestPost,
    MAX(p.LastActivityDate) AS LatestActivity
FROM 
    Posts p
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    p.PostTypeId = 1
    AND p.LastActivityDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY);