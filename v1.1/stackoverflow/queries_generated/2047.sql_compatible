WITH RecentActiveUsers AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        RANK() OVER (ORDER BY MAX(p.LastActivityDate) DESC) AS ActivityRank
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR
    GROUP BY 
        u.Id, u.DisplayName
),
TopScoredPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS NetScore
    FROM 
        Posts p
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '1' MONTH
    GROUP BY 
        p.Id, p.Title
    HAVING 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) > 10
),
BadgedUsers AS (
    SELECT 
        u.Id AS UserId, 
        COUNT(DISTINCT b.Name) AS UniqueBadges
    FROM 
        Users u
    INNER JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id
)
SELECT 
    rau.DisplayName, 
    tsp.Title AS TopPostTitle,
    COALESCE(bu.UniqueBadges, 0) AS UniqueBadgeCount,
    rau.ActivityRank,
    tsp.NetScore
FROM 
    RecentActiveUsers rau
LEFT JOIN 
    TopScoredPosts tsp ON rau.UserId = tsp.PostId
LEFT JOIN 
    BadgedUsers bu ON rau.UserId = bu.UserId
WHERE 
    tsp.NetScore IS NOT NULL 
    OR COALESCE(bu.UniqueBadges, 0) > 5
GROUP BY
    rau.DisplayName,
    tsp.Title,
    COALESCE(bu.UniqueBadges, 0),
    rau.ActivityRank,
    tsp.NetScore
ORDER BY 
    rau.ActivityRank, COALESCE(bu.UniqueBadges, 0) DESC, tsp.NetScore DESC
LIMIT 50;