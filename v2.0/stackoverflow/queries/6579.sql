-- {"query": "6579.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 581}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName AS OwnerDisplayName,
        P.OwnerUserId,
        U.Reputation,
        RANK() OVER (ORDER BY P.Score DESC, P.ViewCount DESC) AS ScoreRank,
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS TypeScoreRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0 AND P.ViewCount > 0
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName AS UserName,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
CommentStats AS (
    SELECT 
        P.Id AS PostId,
        COALESCE(COUNT(C.Id), 0) AS CommentCount
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
    CAST(RP.CreationDate AS DATE) AS CreationDate,
    CAST(RP.LastActivityDate AS DATE) AS LastActivityDate,
    RP.OwnerDisplayName,
    RP.Reputation,
    CS.CommentCount,
    BC.BadgeCount,
    RP.ScoreRank,
    RP.TypeScoreRank,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    SUBSTRING(RP.Title, 1, 30) AS ShortTitle,
    CASE 
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Not Popular'
    END AS ViewTier
FROM 
    RankedPosts RP
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    CAST(RP.CreationDate AS DATE),
    CAST(RP.LastActivityDate AS DATE),
    RP.OwnerDisplayName,
    RP.Reputation,
    CS.CommentCount,
    BC.BadgeCount,
    RP.ScoreRank,
    RP.TypeScoreRank,
    RP.ViewCount
ORDER BY 
    RP.ScoreRank, RP.ViewCount DESC;