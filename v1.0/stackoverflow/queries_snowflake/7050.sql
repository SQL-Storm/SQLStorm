
WITH UserStats AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS PostCount,
        SUM(COALESCE(P.Score, 0)) AS TotalScore,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalViews,
        AVG(CASE WHEN P.CreationDate IS NOT NULL THEN DATEDIFF('hour', P.CreationDate, '2024-10-01 12:34:56') ELSE NULL END) AS AvgPostAgeHours
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE U.Reputation > 1000
    GROUP BY U.Id, U.DisplayName
),
BadgeCounts AS (
    SELECT 
        B.UserId,
        COUNT(B.Id) AS BadgeCount,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges B
    GROUP BY B.UserId
),
PopularPosts AS (
    SELECT 
        P.OwnerUserId,
        P.Title,
        P.Score,
        P.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS PostRank
    FROM Posts P
    WHERE P.PostTypeId = 1 
    ORDER BY P.Score DESC
)
SELECT 
    U.UserId,
    U.DisplayName,
    U.PostCount,
    U.TotalScore,
    U.TotalViews,
    U.AvgPostAgeHours,
    COALESCE(B.BadgeCount, 0) AS TotalBadges,
    COALESCE(B.GoldBadges, 0) AS TotalGoldBadges,
    COALESCE(B.SilverBadges, 0) AS TotalSilverBadges,
    COALESCE(B.BronzeBadges, 0) AS TotalBronzeBadges,
    (SELECT LISTAGG(PP.Title, ', ') WITHIN GROUP (ORDER BY PP.PostRank) FROM PopularPosts PP WHERE PP.OwnerUserId = U.UserId AND PP.PostRank <= 5) AS TopPosts
FROM UserStats U
LEFT JOIN BadgeCounts B ON U.UserId = B.UserId
ORDER BY U.TotalScore DESC, U.PostCount DESC;
