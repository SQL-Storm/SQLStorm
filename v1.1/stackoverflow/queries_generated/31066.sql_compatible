WITH UserPosts AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        COUNT(p.Id) AS TotalPosts, 
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions, 
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers, 
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViews, 
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBounty
    FROM 
        Users AS u
    LEFT JOIN 
        Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes AS v ON p.Id = v.PostId AND v.VoteTypeId = 8  -- BountyStart
    WHERE 
        u.Reputation > 1000 
    GROUP BY 
        u.Id, u.DisplayName
), UserBadges AS (
    SELECT 
        b.UserId, 
        COUNT(*) AS TotalBadges, 
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges, 
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges, 
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Badges AS b
    GROUP BY 
        b.UserId
), UserActivity AS (
    SELECT 
        up.UserId, 
        up.DisplayName, 
        up.TotalPosts, 
        up.Questions, 
        up.Answers, 
        up.TotalViews, 
        up.TotalBounty, 
        ub.TotalBadges, 
        ub.GoldBadges, 
        ub.SilverBadges, 
        ub.BronzeBadges
    FROM 
        UserPosts AS up
    LEFT JOIN 
        UserBadges AS ub ON up.UserId = ub.UserId
)
SELECT 
    ua.UserId, 
    ua.DisplayName, 
    ua.TotalPosts, 
    ua.Questions, 
    ua.Answers, 
    ua.TotalViews, 
    ua.TotalBounty, 
    COALESCE(ua.TotalBadges, 0) AS TotalBadges,
    COALESCE(ua.GoldBadges, 0) AS GoldBadges, 
    COALESCE(ua.SilverBadges, 0) AS SilverBadges, 
    COALESCE(ua.BronzeBadges, 0) AS BronzeBadges
FROM 
    UserActivity AS ua
ORDER BY 
    ua.TotalPosts DESC, ua.TotalViews DESC
LIMIT 100;