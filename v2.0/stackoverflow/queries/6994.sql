WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.PostTypeId,
        P.OwnerUserId,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    LAG(RP.Score, 1) OVER (ORDER BY RP.PostTypeId, RP.rank) AS PreviousScore,
    LEAD(RP.Score, 1) OVER (ORDER BY RP.PostTypeId, RP.rank) AS NextScore,
    CASE 
        WHEN RP.Score > (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = RP.PostTypeId) THEN 'High'
        ELSE 'Low'
    END AS ScoreTier,
    CASE 
        WHEN RP.ViewCount > (SELECT AVG(p3.ViewCount) FROM Posts p3 WHERE p3.PostTypeId = RP.PostTypeId) THEN 'Popular'
        ELSE 'Unpopular'
    END AS ViewTier,
    RP.PostTypeId,
    RP.OwnerUserId
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
WHERE 
    RP.rank <= 10
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    BC.BadgeCount,
    RP.PostTypeId,
    RP.OwnerUserId,
    RP.rank
ORDER BY 
    RP.PostTypeId, RP.rank;