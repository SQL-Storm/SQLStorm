WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM Posts P
    JOIN Users U ON P.OwnerUserId = U.Id
    WHERE P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM Users U
    JOIN Badges B ON U.Id = B.UserId
    WHERE B.Class = 1 AND B.TagBased = FALSE
    GROUP BY U.Id
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RP.OwnerUserId,
    U.DisplayName,
    U.Reputation,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CASE
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Regular'
    END AS Popularity,
    CASE
        WHEN U.Reputation > 10000 THEN 'Legend'
        WHEN U.Reputation > 5000 THEN 'Great'
        ELSE 'Regular'
    END AS ReputationLevel
FROM RankedPosts RP
JOIN Users U ON RP.OwnerUserId = U.Id
LEFT JOIN BadgeCounts BC ON U.Id = BC.UserId
WHERE RP.Rank <= 5
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RP.OwnerUserId,
    U.DisplayName,
    U.Reputation,
    BC.BadgeCount
ORDER BY RP.Score DESC, RP.ViewCount DESC
FETCH FIRST 100 ROWS ONLY;