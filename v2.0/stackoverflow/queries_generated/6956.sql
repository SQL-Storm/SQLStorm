-- {"query": "6956.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 446} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName,
        P.OwnerUserId,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank
    FROM 
        Posts P
        JOIN Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2)
        AND P.Score > 0
        AND P.ViewCount > 100
),
BadgeStats AS (
    SELECT 
        U.Id AS UserId,
        COUNT(DISTINCT B.Id) AS badge_count,
        CASE 
            WHEN COUNT(DISTINCT B.Id) >= 3 THEN 'High'
            WHEN COUNT(DISTINCT B.Id) >= 1 THEN 'Medium'
            ELSE 'Low'
        END AS badge_level
    FROM 
        Users U
        JOIN Badges B ON U.Id = B.UserId
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
    RP.DisplayName,
    RP.Reputation,
    RP.rank,
    BSL.badge_count,
    BSL.badge_level,
    CASE
        WHEN RP.Score > 100 THEN 'High'
        ELSE 'Low'
    END AS score_level,
    CASE
        WHEN RP.ViewCount > 1000 THEN 'High'
        ELSE 'Low'
    END AS view_level
FROM 
    RankedPosts RP
    LEFT JOIN BadgeStats BSL ON RP.OwnerUserId = BSL.UserId
WHERE 
    RP.rank <= 10
ORDER BY 
    RP.Score DESC, 
    RP.ViewCount DESC;
