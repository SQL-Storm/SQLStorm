WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        P.PostTypeId,
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
    WHERE 
        B.Class = 1 AND B.TagBased = FALSE
    GROUP BY 
        U.Id
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    RP.PostTypeId,
    U.DisplayName,
    U.Reputation,
    RC.BadgeCount,
    B.Name AS TopBadge,
    CASE 
        WHEN RP.rank = 1 THEN 'Top Score'
        WHEN RP.rank <= 3 THEN 'Top Viewed'
        ELSE 'Regular'
    END AS RankType
FROM 
    RankedPosts RP
JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts RC ON RP.OwnerUserId = RC.UserId
LEFT JOIN 
    Badges B ON RP.OwnerUserId = B.UserId AND RC.BadgeCount = 1
WHERE 
    RP.rank <= 10
ORDER BY 
    RP.PostTypeId, RP.rank, RP.Score DESC, RP.ViewCount DESC;