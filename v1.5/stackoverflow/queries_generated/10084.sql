-- {"query": "10084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 431} 

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
        SUM(B.Class) AS badge_points,
        MAX(B.Date) AS last_badge_earned
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
    B.last_badge_earned,
    CASE 
        WHEN RP.rank = 1 THEN 'Top Score'
        WHEN RP.rank <= 10 THEN 'Top Ten'
        ELSE 'Other'
    END AS rank_label,
    SUBSTRING(U.AboutMe, 1, 50) AS about_me_short,
    CASE 
        WHEN U.Location IS NULL THEN 'Unknown'
        ELSE U.Location
    END AS location_or_unknown
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgesSummary B ON RP.OwnerUserId = B.UserId
WHERE 
    RP.rank <= 10
ORDER BY 
    RP.rank, RP.Score DESC;
