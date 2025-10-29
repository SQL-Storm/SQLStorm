WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        U.LastAccessDate,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank,
        U.Id AS OwnerUserId
    FROM 
        Posts P
    LEFT JOIN 
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
    RP.Rank,
    RP.DisplayName AS OwnerDisplayName,
    RP.Reputation,
    RP.LastAccessDate,
    BC.BadgeCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Regular'
    END AS Popularity,
    SUBSTRING(RP.Title FROM 1 FOR 50) AS ShortTitle,
    CASE 
        WHEN BC.BadgeCount > 5 THEN 'Elite'
        WHEN BC.BadgeCount > 0 THEN 'Active'
        ELSE 'Inactive'
    END AS UserStatus,
    (
        SELECT 
            COUNT(*) 
        FROM 
            Votes V 
        WHERE 
            V.PostId = RP.Id AND V.VoteTypeId = 2
    ) AS UpvoteCount
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
WHERE 
    RP.Rank <= 10
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.Rank,
    RP.DisplayName,
    RP.Reputation,
    RP.LastAccessDate,
    BC.BadgeCount,
    RP.OwnerUserId
ORDER BY 
    RP.Score DESC, RP.Rank ASC;