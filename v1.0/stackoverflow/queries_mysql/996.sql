
WITH UserBadges AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.DisplayName
),
UserPosts AS (
    SELECT 
        p.OwnerUserId,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews,
        MAX(p.CreationDate) AS LastPostDate
    FROM 
        Posts p
    GROUP BY 
        p.OwnerUserId
),
TopUsers AS (
    SELECT 
        ub.UserId,
        ub.DisplayName,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        up.PostCount,
        up.AvgScore,
        up.TotalViews,
        @rownum := IFNULL(@rownum, 0) + 1 AS ViewRank
    FROM 
        UserBadges ub
    JOIN 
        UserPosts up ON ub.UserId = up.OwnerUserId
    CROSS JOIN (SELECT @rownum := 0) r
    ORDER BY 
        up.TotalViews DESC
)
SELECT 
    tu.DisplayName,
    tu.PostCount,
    tu.AvgScore,
    tu.TotalViews,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    CASE 
        WHEN tu.ViewRank <= 10 THEN 'Top User'
        ELSE 'Regular User'
    END AS UserType,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.UserId = tu.UserId) AS CommentCount
FROM 
    TopUsers tu
WHERE 
    tu.PostCount > 5
    AND (tu.GoldBadges + tu.SilverBadges + tu.BronzeBadges) > 0
ORDER BY 
    tu.TotalViews DESC;
