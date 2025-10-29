-- {"query": "6065.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 536} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName AS OwnerDisplayName,
        U.Reputation,
        U.AccountId,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        B.UserId,
        COUNT(B.Id) AS BadgeCount,
        MAX(B.Class) AS HighestClass
    FROM 
        Badges B
    GROUP BY 
        B.UserId
),
CommentStats AS (
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
    R.Rank,
    R.Id AS PostId,
    R.Title,
    R.Score,
    R.ViewCount,
    R.CreationDate,
    R.LastActivityDate,
    R.OwnerDisplayName,
    R.Reputation,
    R.AccountId,
    B.BadgeCount,
    B.HighestClass,
    CS.CommentCount,
    CS.MaxCommentScore,
    CASE 
        WHEN R.Score > 100 THEN 'High'
        WHEN R.Score BETWEEN 50 AND 100 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    CASE 
        WHEN R.ViewCount > 1000 THEN 'High'
        WHEN R.ViewCount BETWEEN 500 AND 1000 THEN 'Medium'
        ELSE 'Low'
    END AS ViewTier
FROM 
    RankedPosts R
LEFT JOIN 
    BadgeCounts B ON R.AccountId = B.UserId
LEFT JOIN 
    CommentStats CS ON R.Id = CS.PostId
WHERE 
    R.Rank <= 10
ORDER BY 
    R.Score DESC, 
    R.ViewCount DESC;
