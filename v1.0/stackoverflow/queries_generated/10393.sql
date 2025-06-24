-- Performance Benchmarking Query
WITH PostStatistics AS (
    SELECT 
        pt.Name AS PostType,
        COUNT(p.Id) AS TotalPosts,
        AVG(p.Score) AS AvgScore,
        SUM(CASE WHEN p.LastActivityDate > NOW() - INTERVAL '30 days' THEN 1 ELSE 0 END) AS RecentPosts,
        SUM(p.ViewCount) AS TotalViews
    FROM 
        Posts p
    JOIN 
        PostTypes pt ON p.PostTypeId = pt.Id
    GROUP BY 
        pt.Name
),
UserStatistics AS (
    SELECT 
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(c.CreationDate > NOW() - INTERVAL '365 days') AS ActiveComments
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    LEFT JOIN 
        Comments c ON u.Id = c.UserId
    GROUP BY 
        u.DisplayName
)
SELECT 
    ps.PostType,
    ps.TotalPosts,
    ps.AvgScore,
    ps.RecentPosts,
    ps.TotalViews,
    us.DisplayName,
    us.TotalBadges,
    us.ActiveComments
FROM 
    PostStatistics ps
JOIN 
    UserStatistics us ON us.TotalBadges > 0
ORDER BY 
    ps.TotalPosts DESC;
