-- {"query": "6723.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 490}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        P.PostTypeId,
        P.OwnerUserId,
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
        WHEN RP.rank_score <= 3 AND RP.rank_views <= 3 THEN 'Top Score & Views'
        WHEN RP.rank_score <= 3 AND RP.rank_views > 3 THEN 'Top Score'
        WHEN RP.rank_score > 3 AND RP.rank_views <= 3 THEN 'Top Views'
        ELSE 'Regular'
    END AS rank_type,
    CASE 
        WHEN COALESCE(BC.badge_count, 0) >= 5 THEN 'Highly Active'
        ELSE 'Regular'
    END AS activity_level,
    RP.PostTypeId,
    RP.OwnerUserId
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
WHERE 
    (RP.rank_score <= 3 OR RP.rank_views <= 3)
    AND (COALESCE(BC.badge_count, 0) >= 5 OR RP.rank_score <= 3)
ORDER BY 
    RP.PostTypeId, 
    RP.rank_score, 
    RP.rank_views;