-- {"query": "6908.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 454} 

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
BadgesSummary AS (
    SELECT 
        B.UserId,
        COUNT(DISTINCT B.Id) AS total_badges,
        SUM(B.Class) AS badge_points
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
    RP.rank,
    U.DisplayName,
    U.Reputation,
    B.total_badges,
    B.badge_points,
    CASE
        WHEN RP.rank = 1 THEN 'Top'
        WHEN RP.rank BETWEEN 2 AND 10 THEN 'Top 10'
        ELSE 'Other'
    END AS rank_category,
    SUBSTRING(U.Location, 1, 10) AS short_location,
    CASE
        WHEN U.Reputation >= 1000 THEN 'High Rep'
        WHEN U.Reputation >= 500 THEN 'Medium Rep'
        ELSE 'Low Rep'
    END AS rep_category
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgesSummary B ON RP.OwnerUserId = B.UserId
WHERE 
    (RP.rank <= 10 OR RP.Score > 100)
    AND U.Reputation > 100
ORDER BY 
    RP.rank, RP.Score DESC;
