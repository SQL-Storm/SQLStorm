-- {"query": "6206.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 456}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 100
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
CommentMetrics AS (
    SELECT 
        C.PostId,
        COUNT(C.Id) AS CommentCount,
        SUM(C.Score) AS TotalCommentScore
    FROM 
        Comments C
    GROUP BY 
        C.PostId
)
SELECT 
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.OwnerDisplayName,
    COALESCE(RC.BadgeCount, 0) AS OwnerBadgeCount,
    CM.CommentCount,
    CM.TotalCommentScore,
    ROW_NUMBER() OVER (ORDER BY RP.Score DESC, RP.ViewCount DESC) AS GlobalRank
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts RC ON RP.OwnerUserId = RC.UserId
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
ORDER BY 
    GlobalRank;