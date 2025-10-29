-- {"query": "6329.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 492}
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
        U.Id AS OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
        JOIN Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
        JOIN Badges B ON U.Id = B.UserId
    WHERE 
        B.Class = 1 AND B.Date >= (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY)
    GROUP BY 
        U.Id, U.DisplayName
),
CommentedPosts AS (
    SELECT 
        CO.PostId,
        COUNT(CO.Id) AS CommentCount
    FROM 
        Comments CO
    GROUP BY 
        CO.PostId
)
SELECT 
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.Rank,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.LastAccessDate,
    CC.CommentCount,
    BC.BadgeCount,
    CASE
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    CASE
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Not Popular'
    END AS ViewTier
FROM 
    RankedPosts RP
    LEFT JOIN CommentedPosts CC ON RP.Id = CC.PostId
    LEFT JOIN BadgeCounts BC ON RP.OwnerUserId = BC.UserId
WHERE 
    (BC.BadgeCount IS NOT NULL) OR (CC.CommentCount IS NOT NULL)
ORDER BY 
    RP.Rank, RP.ViewCount DESC;