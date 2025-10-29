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
    U.DisplayName,
    U.Reputation,
    B.total_badges,
    B.badge_points,
    CASE
        WHEN RP.rank = 1 THEN 'Top Score'
        WHEN RP.rank <= 10 THEN 'Top Ten'
        ELSE 'Other'
    END AS rank_label,
    SUBSTRING(U.AboutMe FROM 1 FOR 100) AS about_me_snippet,
    CASE
        WHEN U.Location IS NOT NULL THEN (U.Location || ' | ' || COALESCE(U.WebsiteUrl, ''))
        ELSE U.DisplayName
    END AS user_info
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
    U.AboutMe,
    U.Location,
    U.WebsiteUrl
ORDER BY 
    RP.rank, RP.Score DESC;