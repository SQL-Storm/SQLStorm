-- {"query": "6532.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 507}
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
        COUNT(B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        B.Class = 1 AND B.TagBased = FALSE
    GROUP BY 
        U.Id, U.DisplayName
),
CommentStats AS (
    SELECT 
        P.Id AS PostId, 
        COUNT(C.Id) AS CommentCount
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
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CS.CommentCount,
    CASE 
        WHEN RP.Rank <= 10 THEN 'Top'
        WHEN RP.Rank <= 100 THEN 'Middle'
        ELSE 'Bottom'
    END AS RankTier,
    -- Extract first word from Title using standard SQL functions
    CASE
        WHEN POSITION(' ' IN RP.Title) > 0 THEN SUBSTRING(RP.Title FROM 1 FOR POSITION(' ' IN RP.Title) - 1)
        ELSE RP.Title
    END AS FirstWord,
    U.Reputation,
    U.Location,
    U.AboutMe
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerDisplayName = BC.DisplayName
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
JOIN 
    Users U ON RP.OwnerDisplayName = U.DisplayName
ORDER BY 
    RP.Rank;