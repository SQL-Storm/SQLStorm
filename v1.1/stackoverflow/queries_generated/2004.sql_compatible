WITH RankedBadges AS (
    SELECT 
        b.UserId, 
        b.Name, 
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS BadgeRank
    FROM 
        Badges b
),
LatestBadges AS (
    SELECT 
        rb.UserId, 
        rb.Name AS LatestBadgeName
    FROM 
        RankedBadges rb
    WHERE 
        rb.BadgeRank = 1
),
ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation
    FROM 
        Users u
    WHERE 
        u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
),
PopularPosts AS (
    SELECT 
        p.OwnerUserId,
        p.Id AS PostId,
        COUNT(c.Id) AS CommentCount
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365' DAY)
        AND p.Score > 10
    GROUP BY 
        p.OwnerUserId, p.Id
),
UserStatistics AS (
    SELECT 
        au.UserId,
        au.DisplayName,
        au.Reputation,
        lb.LatestBadgeName,
        SUM(COALESCE(pp.CommentCount, 0)) AS TotalComments
    FROM 
        ActiveUsers au
    LEFT JOIN 
        LatestBadges lb ON au.UserId = lb.UserId
    LEFT JOIN 
        PopularPosts pp ON au.UserId = pp.OwnerUserId
    GROUP BY 
        au.UserId, au.DisplayName, au.Reputation, lb.LatestBadgeName
)
SELECT 
    us.UserId,
    us.DisplayName,
    COALESCE(us.LatestBadgeName, 'No Badge') AS RecentBadge,
    COALESCE(us.TotalComments, 0) AS TotalCommentCount,
    us.Reputation
FROM 
    UserStatistics us
WHERE 
    us.Reputation > 1000 OR COALESCE(us.TotalComments, 0) > 50
ORDER BY 
    us.Reputation DESC,
    COALESCE(us.TotalComments, 0) DESC;