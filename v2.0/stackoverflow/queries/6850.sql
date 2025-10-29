-- {"query": "6850.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 412}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
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
    RP.OwnerUserId,
    U.DisplayName,
    U.Reputation,
    COALESCE(B.total_badges, 0) AS total_badges,
    COALESCE(B.badge_points, 0) AS badge_points,
    CASE 
        WHEN RP.rank <= 3 THEN 'Top'
        WHEN RP.rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS rank_category,
    CASE 
        WHEN U.Location IS NOT NULL AND POSITION(',' IN U.Location) > 0
        THEN SUBSTRING(U.Location FROM 1 FOR POSITION(',' IN U.Location) - 1)
        ELSE U.Location
    END AS city,
    CASE 
        WHEN COALESCE(B.total_badges, 0) > 10 THEN 'Active'
        ELSE 'Inactive'
    END AS badge_status
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgesSummary B ON RP.OwnerUserId = B.UserId
WHERE 
    RP.rank <= 10
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    RP.OwnerUserId,
    U.DisplayName,
    U.Reputation,
    B.total_badges,
    B.badge_points,
    U.Location
ORDER BY 
    RP.rank, RP.Score DESC;