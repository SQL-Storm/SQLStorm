-- {"query": "6883.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 503}
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
    COALESCE(CM.CommentCount, 0) AS CommentCount,
    COALESCE(CM.MaxCommentScore, 0) AS MaxCommentScore,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High Scoring'
        WHEN RP.ViewCount > 1000 THEN 'High Viewed'
        ELSE 'Regular'
    END AS Popularity,
    COALESCE(
      NULLIF(
        SUBSTRING(RP.Title FROM 1 FOR (COALESCE(NULLIF(POSITION(' ' IN RP.Title),0) - 1, CHAR_LENGTH(RP.Title)))),
        ''
      ),
      RP.Title
    ) AS FirstWord
FROM 
    RankedPosts RP
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerDisplayName = BC.DisplayName
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    CM.CommentCount,
    CM.MaxCommentScore,
    BC.BadgeCount,
    RP.OwnerDisplayName
ORDER BY 
    RP.Rank, RP.Score DESC;