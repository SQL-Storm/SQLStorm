WITH RankedUsers AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName, 
        U.Reputation, 
        U.CreationDate, 
        U.LastAccessDate, 
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
    FROM Users AS U
    WHERE U.Reputation > 1000
), UserBadges AS (
    SELECT 
        B.UserId, 
        COUNT(*) AS BadgeCount, 
        STRING_AGG(B.Name, ', ') AS BadgeNames
    FROM Badges AS B
    INNER JOIN RankedUsers AS RU ON B.UserId = RU.UserId
    GROUP BY B.UserId
), PopularPosts AS (
    SELECT 
        P.OwnerUserId, 
        P.Id AS PostId, 
        P.Title, 
        P.Score, 
        P.CreationDate, 
        COUNT(C.Id) AS CommentCount
    FROM Posts AS P
    LEFT JOIN Comments AS C ON P.Id = C.PostId
    WHERE P.Score > 10
    GROUP BY P.OwnerUserId, P.Id, P.Title, P.Score, P.CreationDate
    HAVING COUNT(C.Id) > 3
), UserPostStats AS (
    SELECT 
        RU.DisplayName, 
        UB.BadgeCount, 
        UB.BadgeNames, 
        PP.PostId, 
        PP.Title, 
        PP.Score, 
        PP.CommentCount
    FROM RankedUsers AS RU
    JOIN UserBadges AS UB ON RU.UserId = UB.UserId
    LEFT JOIN PopularPosts AS PP ON RU.UserId = PP.OwnerUserId
)
SELECT 
    UPS.DisplayName, 
    UPS.BadgeCount, 
    UPS.BadgeNames, 
    COUNT(UPS.PostId) AS TotalPosts, 
    SUM(UPS.Score) AS TotalScore,
    SUM(UPS.CommentCount) AS TotalComments
FROM UserPostStats AS UPS
GROUP BY UPS.DisplayName, UPS.BadgeCount, UPS.BadgeNames
ORDER BY TotalScore DESC, TotalPosts DESC;