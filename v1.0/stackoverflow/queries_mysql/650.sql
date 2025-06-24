
WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id
),
PopularPosts AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.ViewCount,
        @row_number := IF(@prev_owner_user_id = p.OwnerUserId, @row_number + 1, 1) AS RN,
        @prev_owner_user_id := p.OwnerUserId
    FROM 
        Posts p, (SELECT @row_number := 0, @prev_owner_user_id := NULL) AS vars
    WHERE 
        p.PostTypeId = 1
    ORDER BY 
        p.OwnerUserId, p.ViewCount DESC
)
SELECT 
    u.DisplayName AS UserName,
    COALESCE(ubc.GoldBadges, 0) AS GoldBadges, 
    COALESCE(ubc.SilverBadges, 0) AS SilverBadges, 
    COALESCE(ubc.BronzeBadges, 0) AS BronzeBadges,
    pp.Title AS MostPopularQuestion,
    pp.ViewCount AS MostPopularViewCount,
    CASE 
        WHEN pp.ViewCount IS NULL THEN 'No Questions'
        ELSE 'Has Questions'
    END AS QuestionStatus,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = pp.Id AND v.VoteTypeId = 2) AS UpvoteCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = pp.Id AND v.VoteTypeId = 3) AS DownvoteCount
FROM 
    Users u
LEFT JOIN 
    UserBadgeCounts ubc ON u.Id = ubc.UserId
LEFT JOIN 
    PopularPosts pp ON u.Id = pp.OwnerUserId AND pp.RN = 1
WHERE 
    u.Reputation > 1000
ORDER BY 
    u.Reputation DESC
LIMIT 50;
