-- {"query": "6539.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 389}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        P.OwnerUserId AS UserId,
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
    CASE 
        WHEN RP.rank <= 10 THEN 'Top'
        WHEN RP.rank <= 100 THEN 'Good'
        ELSE 'Average'
    END AS RankStatus,
    BC.BadgeCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score > 50 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreLevel
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.UserId = BC.UserId
WHERE 
    RP.Score > (SELECT AVG(CAST(Score AS NUMERIC)) FROM Posts WHERE PostTypeId = 1)
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.rank,
    RP.UserId,
    BC.BadgeCount
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC
LIMIT 100;