-- {"query": "6739.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 482}
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
        B.Class = 1 AND CAST(B.TagBased AS INTEGER) = 0
    GROUP BY 
        U.Id, U.DisplayName
),
CommentMetrics AS (
    SELECT 
        PC.Id AS PostId,
        COUNT(C.Id) AS comment_count,
        COALESCE(SUM(C.Score), 0) AS total_comment_score
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
    RP.CreationDate,
    RP.rank,
    RP.DisplayName,
    RP.Reputation,
    BC.badge_count,
    CM.comment_count,
    CM.total_comment_score,
    CASE 
        WHEN RP.Score > 100 AND RP.ViewCount > 1000 THEN 'High Impact'
        WHEN RP.Score > 50 AND RP.ViewCount > 500 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS impact_level
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.Id
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
ORDER BY 
    RP.rank, RP.Score DESC;