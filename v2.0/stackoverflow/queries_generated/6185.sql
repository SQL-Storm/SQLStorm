-- {"query": "6185.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 508} 

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
        U.Location,
        U.AboutMe,
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
        B.UserId,
        COUNT(B.Id) AS BadgeCount
    FROM 
        Badges B
    WHERE 
        B.Class = 1 AND B.TagBased = FALSE
    GROUP BY 
        B.UserId
),
CommentStats AS (
    SELECT 
        PC.PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore
    FROM 
        Posts PC
    LEFT JOIN 
        Comments C ON PC.Id = C.PostId
    WHERE 
        PC.PostTypeId = 1
    GROUP BY 
        PC.Id
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.OwnerDisplayName,
    RP.Reputation,
    RP.Location,
    RP.AboutMe,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CS.CommentCount,
    CS.MaxCommentScore,
    CASE 
        WHEN RP.Rank <= 10 THEN 'Top'
        WHEN RP.Rank <= 100 THEN 'Middle'
        ELSE 'Bottom'
    END AS RankGroup
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
WHERE 
    RP.Rank <= 100
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;
