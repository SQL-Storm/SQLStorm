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
        U.AccountId,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName, 
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        B.Class = 1 AND B.TagBased = FALSE
    GROUP BY 
        U.Id, U.DisplayName
),
CommentStats AS (
    SELECT 
        P.Id AS PostId, 
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore,
        MIN(C.Score) AS MinCommentScore
    FROM 
        Posts P
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    GROUP BY 
        P.Id
)
SELECT 
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.Rank,
    RP.CreationDate,
    RP.LastActivityDate,
    U.DisplayName AS OwnerDisplayName,
    U.Reputation,
    U.AccountId,
    BG.BadgeCount,
    CS.CommentCount,
    CS.MaxCommentScore,
    CS.MinCommentScore,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Regular'
    END AS Popularity,
    CASE 
        WHEN RP.LastActivityDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY) THEN 'Active'
        ELSE 'Inactive'
    END AS ActivityStatus
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerDisplayName = U.DisplayName
LEFT JOIN 
    BadgeCounts BG ON U.Id = BG.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
WHERE 
    RP.Rank <= 10
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.Rank,
    RP.CreationDate,
    RP.LastActivityDate,
    U.DisplayName,
    U.Reputation,
    U.AccountId,
    BG.BadgeCount,
    CS.CommentCount,
    CS.MaxCommentScore,
    CS.MinCommentScore
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;