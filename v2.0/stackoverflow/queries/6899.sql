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
        U.LastAccessDate,
        ROW_NUMBER() OVER (ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.LastActivityDate >= P.CreationDate
), 
BadgeCounts AS (
    SELECT 
        B.UserId,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Badges B
    WHERE 
        B.Class = 1 AND B.TagBased = FALSE
    GROUP BY 
        B.UserId
), 
CommentStats AS (
    SELECT 
        PCH.PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore
    FROM 
        PostHistory PCH
    LEFT JOIN 
        Comments C ON PCH.PostId = C.PostId
    WHERE 
        PCH.PostHistoryTypeId = 10
    GROUP BY 
        PCH.PostId
)
SELECT 
    R.Id AS PostId,
    R.Title,
    R.Score,
    R.ViewCount,
    R.CreationDate,
    R.LastActivityDate,
    R.Rank,
    U.DisplayName,
    U.Reputation,
    U.LastAccessDate,
    COALESCE(B.BadgeCount, 0) AS BadgeCount,
    COALESCE(CS.CommentCount, 0) AS CommentCount,
    COALESCE(CS.MaxCommentScore, 0) AS MaxCommentScore,
    CASE 
        WHEN R.Score > 100 THEN 'High'
        WHEN R.ViewCount > 1000 THEN 'Popular'
        ELSE 'Normal'
    END AS PostStatus
FROM 
    RankedPosts R
LEFT JOIN 
    Users U ON R.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts B ON R.OwnerUserId = B.UserId
LEFT JOIN 
    CommentStats CS ON R.Id = CS.PostId
ORDER BY 
    R.Rank;