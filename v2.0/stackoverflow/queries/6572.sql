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
BadgeCounts AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(B.Id) AS badge_count
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        B.Class = 1 AND B.TagBased = FALSE
    GROUP BY 
        U.Id, U.DisplayName
),
CommentMetrics AS (
    SELECT 
        PC.Id,
        PC.Id AS PostId,
        COUNT(C.Id) AS comment_count,
        MAX(C.Score) AS max_comment_score,
        MIN(C.Score) AS min_comment_score
    FROM 
        Posts PC
    LEFT JOIN 
        Comments C ON PC.Id = C.PostId
    GROUP BY 
        PC.Id
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.rank,
    RP.DisplayName,
    RP.Reputation,
    BC.badge_count,
    CM.comment_count,
    CM.max_comment_score,
    CM.min_comment_score,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium'
        ELSE 'Low'
    END AS score_category,
    CASE 
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        WHEN RP.ViewCount BETWEEN 100 AND 1000 THEN 'Moderate'
        ELSE 'Less Popular'
    END AS view_category
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.Id
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
ORDER BY 
    RP.rank, RP.ViewCount DESC
LIMIT 100;