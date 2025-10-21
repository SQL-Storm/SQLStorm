-- {"query": "31066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 533} 

WITH UserPosts AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        COUNT(p.Id) AS TotalPosts, 
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions, 
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers, 
        SUM(p.ViewCount) AS TotalViews, 
        SUM(v.BountyAmount) AS TotalBounty
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8  -- BountyStart
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
        Badges b
    GROUP BY 
        b.UserId
), UserActivity AS (
    SELECT 
        u.UserId, 
        u.DisplayName, 
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
        UserPosts up
    LEFT JOIN 
        UserBadges ub ON up.UserId = ub.UserId
)
SELECT 
    UserId, 
    DisplayName, 
    TotalPosts, 
    Questions, 
    Answers, 
    TotalViews, 
    TotalBounty, 
    COALESCE(TotalBadges, 0) AS TotalBadges,
    COALESCE(GoldBadges, 0) AS GoldBadges, 
    COALESCE(SilverBadges, 0) AS SilverBadges, 
    COALESCE(BronzeBadges, 0) AS BronzeBadges
FROM 
    UserActivity
ORDER BY 
    TotalPosts DESC, TotalViews DESC
LIMIT 100;
