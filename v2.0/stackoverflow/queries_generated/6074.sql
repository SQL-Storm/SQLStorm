-- {"query": "6074.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 456} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank_score,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.ViewCount DESC, P.Score DESC) AS rank_views
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0 AND P.ViewCount > 0
),
BadgeCounts AS (
    SELECT 
        UserId,
        COUNT(DISTINCT Id) AS badge_count
    FROM 
        Badges
    GROUP BY 
        UserId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.rank_score,
    RP.rank_views,
    BC.badge_count,
    CASE 
        WHEN RP.rank_score <= 3 THEN 'Top Scorer'
        WHEN RP.rank_views <= 3 THEN 'Top Viewer'
        ELSE 'Regular'
    END AS rank_category,
    CASE 
        WHEN BC.badge_count >= 5 THEN 'Highly Accomplished'
        WHEN BC.badge_count BETWEEN 3 AND 4 THEN 'Moderately Accomplished'
        ELSE 'Beginner'
    END AS badge_level
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
WHERE 
    (RP.rank_score <= 5 OR RP.rank_views <= 5) AND BC.badge_count IS NOT NULL
ORDER BY 
    RP.PostTypeId, RP.rank_score DESC, RP.rank_views DESC;
