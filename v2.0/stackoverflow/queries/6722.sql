-- {"query": "6722.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 381}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.PostTypeId,
        P.OwnerUserId,
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
BadgesSummary AS (
    SELECT 
        B.UserId,
        COUNT(DISTINCT B.Id) AS total_badges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges
    FROM 
        Badges B
    GROUP BY 
        B.UserId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.PostTypeId,
    RP.rank,
    RP.DisplayName,
    RP.Reputation,
    B.total_badges,
    B.gold_badges,
    B.silver_badges,
    B.bronze_badges
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgesSummary B ON RP.OwnerUserId = B.UserId
WHERE 
    RP.rank <= 10
ORDER BY 
    RP.PostTypeId, RP.rank;