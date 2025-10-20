WITH RankedUsers AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName, 
        U.Reputation, 
        U.CreationDate, 
        U.LastAccessDate, 
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
    FROM Users U
    WHERE U.Reputation > 1000
), UserBadges AS (
    SELECT 
        B.UserId, 
        COUNT(*) AS BadgeCount, 
        STRING_AGG(B.Name, ', ') AS BadgeNames
    FROM Badges B
    JOIN RankedUsers RU ON B.UserId = RU.UserId
    GROUP BY B.UserId
), PopularPosts AS (
    SELECT 
        P.OwnerUserId, 
        P.Id AS PostId, 
        P.Title, 
        P.Score, 
        P.CreationDate, 
        COUNT(C.Id) AS CommentCount
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    WHERE P.Score > 10 
    GROUP BY P.OwnerUserId, P.Id, P.Title, P.Score, P.CreationDate
    HAVING COUNT(C.Id) > 3
), UserPostStats AS (
    SELECT 
        RU.DisplayName, 
        RU.UserId,
        UB.BadgeCount, 
        UB.BadgeNames, 
        PP.PostId, 
        PP.Title, 
        PP.Score, 
        PP.CommentCount
    FROM RankedUsers RU
    JOIN UserBadges UB ON RU.UserId = UB.UserId
    LEFT JOIN PopularPosts PP ON RU.UserId = PP.OwnerUserId
)
SELECT 
    UPS.DisplayName, 
    UPS.BadgeCount, 
    UPS.BadgeNames, 
    COUNT(UPS.PostId) AS TotalPosts, 
    SUM(COALESCE(UPS.Score,0)) AS TotalScore,
    SUM(COALESCE(UPS.CommentCount,0)) AS TotalComments
FROM UserPostStats UPS
GROUP BY UPS.DisplayName, UPS.BadgeCount, UPS.BadgeNames
ORDER BY TotalScore DESC, TotalPosts DESC;