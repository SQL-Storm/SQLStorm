WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        P.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId NOT IN (3, 4, 5)
),
BadgesSummary AS (
    SELECT 
        B.UserId,
        COUNT(DISTINCT B.Id) AS total_badges,
        SUM(B.Class) AS badge_class_total
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
    RP.DisplayName,
    RP.Reputation,
    B.total_badges,
    B.badge_class_total,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score > 50 THEN 'Medium'
        ELSE 'Low'
    END AS score_category,
    CASE 
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        WHEN RP.ViewCount > 100 THEN 'Moderate'
        ELSE 'Less Popular'
    END AS view_category
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgesSummary B ON RP.OwnerUserId = B.UserId
WHERE 
    RP.rank <= 10
ORDER BY 
    RP.Score DESC, 
    RP.ViewCount DESC;