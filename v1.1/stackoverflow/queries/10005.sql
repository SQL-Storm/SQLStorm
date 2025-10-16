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
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank,
        P.OwnerUserId,
        P.PostTypeId
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
    GROUP BY 
        U.Id, U.DisplayName
),
CommentStats AS (
    SELECT 
        P.Id AS PostId, 
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore,
        MIN(COALESCE(C.Score, 0)) AS MinCommentScore
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
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RC.BadgeCount,
    COALESCE(CS.CommentCount, 0) AS CommentCount,
    CS.MaxCommentScore,
    CS.MinCommentScore,
    CASE 
        WHEN RP.Score > 100 THEN 'High Scoring'
        WHEN RP.ViewCount > 1000 THEN 'High Viewed'
        ELSE 'Regular'
    END AS PostStatus
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts RC ON RP.OwnerUserId = RC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RC.BadgeCount,
    CS.CommentCount,
    CS.MaxCommentScore,
    CS.MinCommentScore
ORDER BY 
    RP.Rank, RP.Score DESC;