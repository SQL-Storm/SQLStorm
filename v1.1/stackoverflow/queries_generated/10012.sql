-- {"query": "10012.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 483} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName AS Owner,
        U.Reputation,
        U.Location,
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
    JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
CommentStats AS (
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
    RP.LastActivityDate,
    RP.Rank,
    B.BadgeCount,
    CS.CommentCount,
    CS.MaxCommentScore,
    CS.MinCommentScore,
    CASE
        WHEN RP.Rank <= 3 THEN 'Top'
        WHEN RP.Rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankStatus
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts B ON RP.Owner = B.DisplayName
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
WHERE 
    RP.Rank <= 10
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;
