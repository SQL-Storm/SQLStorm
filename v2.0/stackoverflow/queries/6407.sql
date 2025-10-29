-- {"query": "6407.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 409}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        P.OwnerUserId,
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
    RP.rank,
    BC.BadgeCount,
    CASE 
        WHEN RP.Score > 1000 THEN 'High'
        WHEN RP.Score BETWEEN 500 AND 1000 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    SUBSTRING(RP.Title FROM 1 FOR 50) AS ShortTitle,
    CASE 
        WHEN COALESCE(BC.BadgeCount, 0) >= 5 THEN 'Elite'
        WHEN COALESCE(BC.BadgeCount, 0) BETWEEN 3 AND 4 THEN 'Advanced'
        ELSE 'Basic'
    END AS BadgeLevel
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
WHERE 
    RP.rank <= 10
ORDER BY 
    RP.Score DESC, 
    RP.ViewCount DESC;