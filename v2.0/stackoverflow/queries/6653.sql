WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.Id AS OwnerUserId,
        U.DisplayName,
        U.Reputation,
        U.LastAccessDate,
        ROW_NUMBER() OVER (ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
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
    RP.Rank,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.DisplayName,
    RP.Reputation,
    RP.LastAccessDate,
    BC.BadgeCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Regular'
    END AS Popularity,
    CASE 
        WHEN RP.CreationDate < DATE '2020-01-01' THEN 'Old'
        ELSE 'Recent'
    END AS Age,
    SUBSTRING(RP.Title FROM 1 FOR 50) AS ShortTitle,
    U.Location,
    U.WebsiteUrl,
    U.AboutMe
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
JOIN 
    Users U ON RP.OwnerUserId = U.Id
WHERE 
    (RP.Score > (SELECT AVG(P2.Score) FROM Posts P2 WHERE P2.PostTypeId = 1) OR RP.ViewCount > (SELECT AVG(P3.ViewCount) FROM Posts P3 WHERE P3.PostTypeId = 1))
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.Rank,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.DisplayName,
    RP.Reputation,
    RP.LastAccessDate,
    BC.BadgeCount,
    RP.CreationDate,
    RP.Title,
    U.Location,
    U.WebsiteUrl,
    U.AboutMe,
    RP.OwnerUserId
ORDER BY 
    RP.Rank;