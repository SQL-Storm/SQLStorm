WITH UserBadgeCounts AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName, 
        COUNT(B.Id) FILTER (WHERE B.Class = 1) AS GoldBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 2) AS SilverBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 3) AS BronzeBadges,
        COUNT(B.Id) AS TotalBadges
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
),
PostStatistics AS (
    SELECT 
        P.OwnerUserId,
        COUNT(P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        MAX(P.CreationDate) AS LastPostDate
    FROM 
        Posts P
    GROUP BY 
        P.OwnerUserId
),
CombinedStats AS (
    SELECT 
        UB.UserId,
        UB.DisplayName,
        COALESCE(PS.TotalPosts, 0) AS TotalPosts,
        COALESCE(PS.TotalQuestions, 0) AS TotalQuestions,
        COALESCE(PS.TotalAnswers, 0) AS TotalAnswers,
        COALESCE(UB.GoldBadges, 0) AS GoldBadges,
        COALESCE(UB.SilverBadges, 0) AS SilverBadges,
        COALESCE(UB.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(UB.TotalBadges, 0) AS TotalBadges
    FROM 
        UserBadgeCounts UB
    LEFT JOIN 
        PostStatistics PS ON UB.UserId = PS.OwnerUserId
)
SELECT 
    C.DisplayName,
    C.TotalPosts,
    C.TotalQuestions,
    C.TotalAnswers,
    C.GoldBadges,
    C.SilverBadges,
    C.BronzeBadges,
    C.TotalBadges,
    RANK() OVER (ORDER BY C.TotalPosts DESC) AS PostRank,
    RANK() OVER (ORDER BY C.TotalBadges DESC) AS BadgeRank
FROM 
    CombinedStats C
WHERE 
    C.TotalPosts > 0 AND 
    (C.GoldBadges + C.SilverBadges + C.BronzeBadges) > 0
ORDER BY 
    C.TotalPosts DESC, C.TotalBadges DESC
LIMIT 10;

-- Outer join with a subquery that identifies user activity in the last 30 days 
SELECT 
    U.DisplayName, 
    COUNT(P.Id) AS RecentPostCount
FROM 
    Users U
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId AND P.CreationDate >= NOW() - INTERVAL '30 days'
GROUP BY 
    U.Id
HAVING 
    COUNT(P.Id) >= 5
ORDER BY 
    RecentPostCount DESC;
