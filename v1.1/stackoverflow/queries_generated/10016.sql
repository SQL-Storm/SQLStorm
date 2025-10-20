-- {"query": "10016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 421} 

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
    FROM Posts P
    JOIN Users U ON P.OwnerUserId = U.Id
    WHERE P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM Users U
    JOIN Badges B ON U.Id = B.UserId
    WHERE B.Class = 1 AND B.TagBased = FALSE
    GROUP BY U.Id
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    U.DisplayName,
    U.Reputation,
    BC.BadgeCount,
    CASE
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Regular'
    END AS Popularity,
    CASE
        WHEN U.Reputation > 10000 THEN 'Legend'
        WHEN U.Reputation > 5000 THEN 'Great'
        ELSE 'Regular'
    END AS ReputationLevel
FROM RankedPosts RP
JOIN Users U ON RP.OwnerUserId = U.Id
LEFT JOIN BadgeCounts BC ON U.Id = BC.UserId
WHERE RP.Rank <= 5
ORDER BY RP.Score DESC, RP.ViewCount DESC
LIMIT 100;
