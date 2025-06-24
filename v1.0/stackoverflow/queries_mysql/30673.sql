
WITH RECURSIVE UserReputationHistory AS (
    SELECT 
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate,
        U.DisplayName,
        1 AS RankLevel
    FROM 
        Users U
    WHERE 
        U.Reputation > 0
    UNION ALL
    SELECT 
        U.Id,
        U.Reputation + 50 AS Reputation,
        U.CreationDate,
        U.DisplayName,
        URH.RankLevel + 1 AS RankLevel
    FROM 
        Users U
    JOIN 
        UserReputationHistory URH ON U.Id = URH.UserId
    WHERE 
        URH.RankLevel < 5 
)
, RecentPosts AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.Score,
        P.CreationDate,
        P.OwnerUserId,
        @row_number := IF(@current_user_id = P.OwnerUserId, @row_number + 1, 1) AS PostRank,
        @current_user_id := P.OwnerUserId
    FROM 
        Posts P,
        (SELECT @row_number := 0, @current_user_id := NULL) AS vars
    WHERE 
        P.CreationDate > NOW() - INTERVAL 30 DAY
    ORDER BY 
        P.OwnerUserId, P.CreationDate DESC
)
, UserBadges AS (
    SELECT 
        U.Id AS UserId,
        COUNT(B.Id) AS TotalBadges,
        GROUP_CONCAT(B.Name SEPARATOR ', ') AS BadgeNames
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON B.UserId = U.Id
    GROUP BY 
        U.Id
)
SELECT 
    U.DisplayName,
    U.Reputation,
    COALESCE(URH.RankLevel, 0) AS ReputationRank,
    RP.PostId,
    RP.Title AS RecentPostTitle,
    RP.Score AS PostScore,
    UB.TotalBadges,
    UB.BadgeNames
FROM 
    Users U
LEFT JOIN 
    UserReputationHistory URH ON U.Id = URH.UserId
LEFT JOIN 
    RecentPosts RP ON U.Id = RP.OwnerUserId AND RP.PostRank = 1
LEFT JOIN 
    UserBadges UB ON U.Id = UB.UserId
WHERE 
    (U.Reputation > 1000 OR UB.TotalBadges > 5) 
ORDER BY 
    U.Reputation DESC, UB.TotalBadges DESC
LIMIT 50;
