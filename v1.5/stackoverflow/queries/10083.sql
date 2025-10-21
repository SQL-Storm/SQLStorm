WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
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
    LEFT JOIN 
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
    RP.LastActivityDate,
    RP.Rank,
    RP.DisplayName,
    RP.Reputation,
    BC.BadgeCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    SUBSTRING(REGEXP_REPLACE(RP.DisplayName, '^[^A-Za-z0-9]+|[^A-Za-z0-9]+$', '', 'g'), 1, NULL) AS Initials,
    CASE 
        WHEN COALESCE(BC.BadgeCount, 0) >= 5 THEN 'Active'
        ELSE 'Inactive'
    END AS BadgeActivity
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.Id = BC.UserId
WHERE 
    RP.Rank <= 10
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RP.DisplayName,
    RP.Reputation,
    BC.BadgeCount
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;