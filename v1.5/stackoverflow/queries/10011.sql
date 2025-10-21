WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
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
        B.Class = 1 AND B.Date >= DATE '2023-01-01'
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
    RP.DisplayName,
    RP.Reputation,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CASE 
        WHEN RP.rank <= 3 THEN 'Top'
        WHEN RP.rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankStatus,
    SUBSTRING(COALESCE(U.AboutMe, ''), 1, 50) AS AboutMeSnippet
FROM 
    RankedPosts RP
JOIN 
    Users U ON RP.Id = U.Id
LEFT JOIN 
    BadgeCounts BC ON RP.Id = BC.UserId
WHERE 
    RP.rank <= 10 AND U.Reputation > 100
ORDER BY 
    RP.rank, RP.Score DESC;