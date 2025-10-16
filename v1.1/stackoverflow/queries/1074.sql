WITH UserReputation AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName, 
        U.Reputation,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
    FROM Users U
), 
PopularPosts AS (
    SELECT 
        P.Id AS PostId, 
        P.Title, 
        P.Score, 
        P.CreationDate,
        COUNT(C.Id) AS CommentCount,
        COALESCE(SUM(V.BountyAmount), 0) AS TotalBounty
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId = 8 -- BountyStart
    WHERE P.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY P.Id, P.Title, P.Score, P.CreationDate
    HAVING COUNT(C.Id) > 0
), 
UserBadges AS (
    SELECT 
        B.UserId,
        COUNT(B.Id) AS BadgeCount
    FROM Badges B
    WHERE B.Date >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5 years'
    GROUP BY B.UserId
),
UserPostStats AS (
    SELECT 
        U.Id AS UserId, 
        COALESCE(SUM(P.ViewCount), 0) AS TotalViews,
        COALESCE(SUM(P.AnswerCount), 0) AS TotalAnswers
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    GROUP BY U.Id
)
SELECT 
    UR.DisplayName,
    UR.Reputation,
    UR.ReputationRank,
    PP.PostId,
    PP.Title,
    PP.Score,
    PP.CommentCount,
    PP.TotalBounty,
    UB.BadgeCount,
    UPS.TotalViews,
    UPS.TotalAnswers
FROM UserReputation UR
JOIN PopularPosts PP ON PP.CommentCount > 5
LEFT JOIN UserBadges UB ON UR.UserId = UB.UserId
LEFT JOIN UserPostStats UPS ON UR.UserId = UPS.UserId
WHERE UR.Reputation > 1000
ORDER BY UR.Reputation DESC, PP.TotalBounty DESC
FETCH FIRST 10 ROWS ONLY;