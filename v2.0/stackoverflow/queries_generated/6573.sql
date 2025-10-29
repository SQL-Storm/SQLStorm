-- {"query": "6573.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 450} 

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
        U.LastAccessDate,
        ROW_NUMBER() OVER (ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
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
        B.Class = 1 AND B.TagBased = 0
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
    RP.LastAccessDate,
    BC.BadgeCount,
    CASE 
        WHEN RP.Score > (SELECT AVG(RP2.Score) FROM RankedPosts RP2) THEN 'High'
        WHEN RP.Score < (SELECT AVG(RP2.Score) FROM RankedPosts RP2) THEN 'Low'
        ELSE 'Average'
    END AS ScoreTier,
    CASE 
        WHEN RP.ViewCount > (SELECT AVG(RP2.ViewCount) FROM RankedPosts RP2) THEN 'Popular'
        WHEN RP.ViewCount < (SELECT AVG(RP2.ViewCount) FROM RankedPosts RP2) THEN 'Unpopular'
        ELSE 'Average'
    END AS ViewTier
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
ORDER BY 
    RP.Rank;
