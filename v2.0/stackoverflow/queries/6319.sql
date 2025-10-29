-- {"query": "6319.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 594}
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
        B.Class = 1 AND B.Date >= (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY)
    GROUP BY 
        U.Id, U.DisplayName
),
CommentMetrics AS (
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
    RP.CreationDate,
    RP.Rank,
    U.DisplayName AS OwnerDisplayName,
    U.Reputation,
    U.LastAccessDate,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CM.CommentCount,
    CM.MaxCommentScore,
    CM.MinCommentScore,
    CASE
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Regular'
    END AS Popularity,
    CASE
        WHEN U.Reputation > 10000 THEN 'Veteran'
        WHEN U.Reputation > 1000 THEN 'Experienced'
        ELSE 'Newbie'
    END AS UserLevel
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts BC ON U.Id = BC.UserId
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.Rank,
    RP.OwnerUserId,
    U.DisplayName,
    U.Reputation,
    U.LastAccessDate,
    BC.BadgeCount,
    CM.CommentCount,
    CM.MaxCommentScore,
    CM.MinCommentScore
ORDER BY 
    RP.Rank, RP.Score DESC, RP.ViewCount DESC;