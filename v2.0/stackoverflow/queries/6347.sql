WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        U.Id AS UserId,
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
    LAG(RP.Score) OVER (ORDER BY RP.rank) AS PreviousRankScore,
    LEAD(RP.Score) OVER (ORDER BY RP.rank) AS NextRankScore,
    CASE 
        WHEN RP.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'High'
        ELSE 'Low'
    END AS ScoreTier,
    CASE 
        WHEN RP.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) THEN 'Popular'
        ELSE 'Unpopular'
    END AS ViewTier
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.UserId = BC.UserId
WHERE 
    RP.rank BETWEEN 1 AND 100
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.UserId,
    BC.BadgeCount,
    RP.rank
ORDER BY 
    RP.rank;