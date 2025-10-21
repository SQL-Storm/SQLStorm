-- {"query": "10043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 498} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
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
        U.Id AS UserId,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        B.Class = 1 AND B.Date >= '2022-01-01'
    GROUP BY 
        U.Id
),
CommentMetrics AS (
    SELECT 
        P.Id AS PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore
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
    COALESCE(CM.CommentCount, 0) AS CommentCount,
    COALESCE(CM.MaxCommentScore, 0) AS MaxCommentScore,
    RP.rank,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    U.DisplayName,
    U.Reputation,
    CASE 
        WHEN RP.rank <= 10 THEN 'Top'
        WHEN RP.rank <= 100 THEN 'Middle'
        ELSE 'Bottom'
    END AS RankTier
FROM 
    RankedPosts RP
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
JOIN 
    Users U ON RP.OwnerUserId = U.Id
ORDER BY 
    RP.rank, RP.Score DESC;
