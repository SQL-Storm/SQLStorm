
WITH RankedUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        @row_number := IF(@prev_reputation = u.Reputation, @row_number, @row_number + 1) AS UserRank,
        @prev_reputation := u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    CROSS JOIN (SELECT @row_number := 0, @prev_reputation := NULL) AS vars
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount
    FROM 
        RankedUsers
    WHERE 
        UserRank <= 10
),
PostStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositivePosts,
        SUM(CASE WHEN p.Score < 0 THEN 1 ELSE 0 END) AS NegativePosts,
        AVG(COALESCE(p.ViewCount, 0)) AS AvgViewCount
    FROM 
        Posts p
    GROUP BY 
        p.OwnerUserId
),
UserBadges AS (
    SELECT 
        b.UserId,
        GROUP_CONCAT(b.Name SEPARATOR ', ') AS BadgeNames
    FROM 
        Badges b
    WHERE 
        b.Class = 1 
    GROUP BY 
        b.UserId
)
SELECT 
    u.DisplayName,
    u.Reputation,
    ps.TotalPosts,
    ps.PositivePosts,
    ps.NegativePosts,
    ps.AvgViewCount,
    COALESCE(ub.BadgeNames, 'None') AS GoldBadges
FROM 
    TopUsers u
LEFT JOIN 
    PostStats ps ON u.UserId = ps.OwnerUserId
LEFT JOIN 
    UserBadges ub ON u.UserId = ub.UserId
ORDER BY 
    u.Reputation DESC;
