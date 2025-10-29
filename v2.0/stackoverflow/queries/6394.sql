-- {"query": "6394.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 595}
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
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        B.Class = 1 AND B.TagBased = FALSE
    GROUP BY 
        U.Id, U.DisplayName
),
CommentMetrics AS (
    SELECT 
        PC.Id AS PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore,
        MIN(COALESCE(C.Score, 0)) AS MinCommentScore
    FROM 
        Posts PC
    LEFT JOIN 
        Comments C ON PC.Id = C.PostId
    GROUP BY 
        PC.Id
)
SELECT 
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RC.BadgeCount,
    CM.CommentCount,
    CM.MaxCommentScore,
    CM.MinCommentScore,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    -- portability: use standard SQL to get first word
    SUBSTRING(RP.Title FROM 1 FOR (CASE WHEN POSITION(' ' IN RP.Title) = 0 THEN CHAR_LENGTH(RP.Title) ELSE POSITION(' ' IN RP.Title)-1 END)) AS FirstWord,
    CASE 
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Not Popular'
    END AS Popularity,
    U.Reputation,
    U.DisplayName AS OwnerDisplayName,
    U.Location,
    U.AboutMe
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts RC ON RP.OwnerDisplayName = RC.DisplayName
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
LEFT JOIN 
    Users U ON RP.OwnerDisplayName = U.DisplayName
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RC.BadgeCount,
    CM.CommentCount,
    CM.MaxCommentScore,
    CM.MinCommentScore,
    ScoreTier,
    FirstWord,
    Popularity,
    U.Reputation,
    U.DisplayName,
    U.Location,
    U.AboutMe
ORDER BY 
    RP.Rank, RP.Score DESC, RP.ViewCount DESC;