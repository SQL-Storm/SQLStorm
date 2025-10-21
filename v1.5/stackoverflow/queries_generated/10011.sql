-- {"query": "10011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 417} 

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
        B.Class = 1 AND B.Date >= '2023-01-01'
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
    U.DisplayName,
    U.Reputation,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CASE 
        WHEN RP.rank <= 3 THEN 'Top'
        WHEN RP.rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankStatus,
    SUBSTRING(U.AboutMe, 1, 50) AS AboutMeSnippet
FROM 
    RankedPosts RP
JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
WHERE 
    RP.rank <= 10 AND U.Reputation > 100
ORDER BY 
    RP.rank, RP.Score DESC;
