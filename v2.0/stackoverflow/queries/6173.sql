-- {"query": "6173.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 472}
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
        P.PostTypeId = 1 AND P.Score > 0 AND P.LastActivityDate > P.CreationDate
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
CommentMetrics AS (
    SELECT 
        PC.PostId,
        COUNT(PC.Id) AS CommentCount,
        MAX(PC.Score) AS MaxCommentScore
    FROM 
        Comments PC
    GROUP BY 
        PC.PostId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CM.CommentCount,
    CASE 
        WHEN CM.CommentCount > 0 THEN CAST(CM.MaxCommentScore AS DECIMAL) / CM.CommentCount
        ELSE 0
    END AS AvgCommentScore,
    U.DisplayName AS OwnerDisplayName,
    U.Reputation,
    U.Location,
    U.AboutMe,
    U.WebsiteUrl
FROM 
    RankedPosts RP
JOIN 
    Users U ON RP.OwnerDisplayName = U.DisplayName
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
    RP.LastActivityDate,
    RP.Rank,
    BC.BadgeCount,
    CM.CommentCount,
    CM.MaxCommentScore,
    U.DisplayName,
    U.Reputation,
    U.Location,
    U.AboutMe,
    U.WebsiteUrl
ORDER BY 
    RP.Rank, RP.Score DESC, RP.ViewCount DESC;