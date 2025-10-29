SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
    MAX(u.LastAccessDate) AS LastAccess,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.LastActivityDate DESC) AS RecentActivityRank
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
WHERE 
    u.Reputation > 1000
    AND p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.LastAccessDate, p.LastActivityDate
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalQuestionScore DESC, 
    LastAccess DESC;