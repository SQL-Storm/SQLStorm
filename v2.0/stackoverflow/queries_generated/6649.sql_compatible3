SELECT 
    u.id,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 1 THEN p.Id END) AS TotalTitleEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 2 THEN p.Id END) AS TotalBodyEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN p.Id END) AS TotalCloses,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN p.Id END) AS TotalReopens,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.CreationDate) AS FirstPostDate,
    MAX(p.LastActivityDate) AS LastActivityDate,
    b.Name AS LatestBadge,
    v.Name AS LatestBadgeType,
    v.Date AS LatestBadgeDate,
    MAX(v.rn) AS RecencyRank
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         UserId, 
         Name, 
         Date, 
         ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY Date DESC) AS rn
     FROM Badges) v ON u.Id = v.UserId AND v.rn = 1
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 1000
    AND (p.PostTypeId IS NULL OR p.PostTypeId IN (1, 2))
    AND (ph.PostHistoryTypeId IN (1, 2, 10, 11) OR b.Id IS NOT NULL)
GROUP BY 
    u.Id,
    u.DisplayName,
    b.Name,
    v.Name,
    v.Date,
    v.rn
HAVING 
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN p.Id END) > 0
ORDER BY 
    TotalPosts DESC, 
    HighestScoredPost DESC;