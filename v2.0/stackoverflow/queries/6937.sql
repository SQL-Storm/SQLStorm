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
        P.PostTypeId NOT IN (3, 4, 5)
),
BadgeCounts AS (
    SELECT 
        UserId,
        COUNT(DISTINCT Id) AS badge_count
    FROM 
        Badges
    GROUP BY 
        UserId
),
CommentStats AS (
    SELECT 
        PostId,
        COUNT(*) AS comment_count,
        MAX(CASE WHEN C.UserId IS NOT NULL THEN 1 ELSE 0 END) AS has_user_comment
    FROM 
        Comments C
    GROUP BY 
        PostId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerUserId,
    RP.rank,
    COALESCE(BC.badge_count, 0) AS badge_count,
    COALESCE(CS.comment_count, 0) AS comment_count,
    CASE 
        WHEN COALESCE(CS.has_user_comment, 0) = 1 THEN 'Yes'
        ELSE 'No'
    END AS has_user_comment,
    SUBSTRING(RP.Title FROM 1 FOR 50) || '...' AS short_title,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        ELSE 'Low'
    END AS score_category
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
WHERE 
    RP.rank <= 10
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerUserId,
    RP.rank,
    BC.badge_count,
    CS.comment_count,
    CS.has_user_comment
ORDER BY 
    RP.Score DESC, RP.rank ASC;