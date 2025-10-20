WITH RECURSIVE RecursiveUserHierarchy AS (
    SELECT 
        Id, 
        DisplayName, 
        Reputation,
        LastAccessDate,
        1 AS Level
    FROM 
        Users
    WHERE 
        Reputation = (SELECT MAX(Reputation) FROM Users)
    
    UNION ALL
    
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation,
        u.LastAccessDate,
        r.Level + 1
    FROM 
        Users u
    INNER JOIN 
        RecursiveUserHierarchy r 
        ON u.Reputation < r.Reputation
        AND u.LastAccessDate > r.LastAccessDate
)
SELECT 
    h.Level,
    h.DisplayName, 
    h.Reputation,
    b.Name AS Badge,
    COUNT(p.Id) AS PostCount,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.Score) AS AvgScore,
    MAX(p.LastActivityDate) AS MostRecentActivity
FROM 
    RecursiveUserHierarchy h
LEFT JOIN 
    Badges b ON h.Id = b.UserId
LEFT JOIN 
    Posts p ON h.Id = p.OwnerUserId
WHERE 
    p.Score > 0
GROUP BY 
    h.Level,
    h.DisplayName, 
    h.Reputation,
    b.Name
ORDER BY 
    h.Level DESC, 
    TotalViews DESC;