-- {"query": "6415.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 401} 

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
    GROUP BY 
        U.Id
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    TO_CHAR(RP.CreationDate, 'YYYY-MM-DD') AS CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.rank,
    BC.BadgeCount,
    SUM(V.Score) OVER (PARTITION BY RP.Id ORDER BY V.CreationDate) AS RunningScore,
    CASE 
        WHEN RP.rank = 1 THEN 'Top'
        WHEN RP.rank BETWEEN 2 AND 10 THEN 'Top 10'
        ELSE 'Other'
    END AS RankGroup
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.UserId = BC.UserId
LEFT JOIN 
    Votes V ON RP.Id = V.PostId
WHERE 
    RP.Score > 100
ORDER BY 
    RunningScore DESC, RP.rank ASC
LIMIT 100;
