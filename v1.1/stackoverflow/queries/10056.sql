WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName AS OwnerDisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
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
        U.DisplayName,
        U.Reputation,
        COUNT(B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
CommentedPosts AS (
    SELECT 
        P.Id AS PostId, 
        COUNT(C.Id) AS CommentCount
    FROM 
        Posts P
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    GROUP BY 
        P.Id
)
SELECT 
    RP.Id, 
    RP.Title, 
    RP.Score, 
    RP.ViewCount, 
    RP.CreationDate, 
    RP.LastActivityDate, 
    RP.Rank,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CP.CommentCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High Scoring'
        WHEN RP.ViewCount > 1000 THEN 'High Viewed'
        ELSE 'Regular'
    END AS Popularity,
    CASE
        WHEN RP.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY) THEN 'Active'
        ELSE 'Inactive'
    END AS ActivityStatus
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerDisplayName = BC.DisplayName
LEFT JOIN 
    CommentedPosts CP ON RP.Id = CP.PostId
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    BC.BadgeCount,
    CP.CommentCount,
    RP.OwnerDisplayName,
    RP.Reputation
ORDER BY 
    RP.Rank, RP.Score DESC, RP.ViewCount DESC;