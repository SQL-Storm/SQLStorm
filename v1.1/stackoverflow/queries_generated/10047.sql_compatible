WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
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
    LEFT JOIN 
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
    RP.LastActivityDate,
    RP.Rank,
    RP.OwnerUserId,
    U.DisplayName,
    U.Reputation,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CASE 
        WHEN RP.Rank <= 3 THEN 'Top'
        WHEN RP.Rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankStatus,
    SUBSTRING(COALESCE(U.AboutMe, '') FROM 1 FOR 50) AS AboutMeSnippet,
    CASE 
        WHEN U.Reputation >= 10000 THEN 'Veteran'
        WHEN U.Reputation >= 5000 THEN 'Experienced'
        ELSE 'Newbie'
    END AS ReputationLevel
FROM 
    RankedPosts RP
JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
WHERE 
    RP.Rank <= 10
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RP.OwnerUserId,
    U.DisplayName,
    U.Reputation,
    BC.BadgeCount,
    U.AboutMe
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;