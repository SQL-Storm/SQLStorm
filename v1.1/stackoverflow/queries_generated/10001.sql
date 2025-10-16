-- {"query": "10001.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 470} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        U.LastAccessDate,
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
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        B.Class = 1 AND B.Date >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY 
        U.Id, U.DisplayName
),
CommentMetrics AS (
    SELECT 
        PC.PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore
    FROM 
        Posts PC
    LEFT JOIN 
        Comments C ON PC.Id = C.PostId
    GROUP BY 
        PC.PostId
)
SELECT 
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.Rank,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.LastAccessDate,
    BC.BadgeCount,
    CM.CommentCount,
    COALESCE(CM.MaxCommentScore, 0) AS MaxCommentScore
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
WHERE 
    RP.Rank <= 10
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;
