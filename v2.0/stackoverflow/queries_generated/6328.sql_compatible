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
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        UserId,
        COUNT(DISTINCT Id) AS BadgeCount
    FROM 
        Badges
    GROUP BY 
        UserId
),
CommentStats AS (
    SELECT 
        PostId,
        COUNT(Id) AS CommentCount,
        MAX(Score) AS MaxCommentScore
    FROM 
        Comments
    GROUP BY 
        PostId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    CAST(RP.CreationDate AS DATE) AS CreationDate,
    CAST(RP.LastActivityDate AS DATE) AS LastActivityDate,
    RP.OwnerUserId,
    RP.DisplayName,
    RP.Reputation,
    RP.rank,
    BC.BadgeCount,
    CS.CommentCount,
    COALESCE(CS.MaxCommentScore, 0) AS MaxCommentScore,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        ELSE 'Low'
    END AS ScoreTier,
    CASE 
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Not Popular'
    END AS ViewTier
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
WHERE 
    RP.rank <= 5
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    CAST(RP.CreationDate AS DATE),
    CAST(RP.LastActivityDate AS DATE),
    RP.OwnerUserId,
    RP.DisplayName,
    RP.Reputation,
    RP.rank,
    BC.BadgeCount,
    CS.CommentCount,
    CS.MaxCommentScore
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;