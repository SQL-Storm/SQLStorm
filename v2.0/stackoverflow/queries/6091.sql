-- {"query": "6091.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 497}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
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
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    COALESCE(CS.CommentCount, 0) AS CommentCount,
    COALESCE(CS.MaxCommentScore, 0) AS MaxCommentScore,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    -- Portable replacement for SUBSTRING_INDEX: take last two words and then first of those.
    -- Works in many dialects using reverse/regexp_substr is not portable; use simple expression assuming words separated by spaces.
    -- Here: take the last two words by splitting on space is not supported universally; use simple approach to get last word if available.
    CASE
        WHEN RP.Title IS NULL THEN NULL
        WHEN LENGTH(RP.Title) - LENGTH(REPLACE(RP.Title, ' ', '')) = 0 THEN RP.Title
        ELSE
            -- Get the second to last word if exists, otherwise last word.
            TRIM(SPLIT_PART(RP.Title, ' ', GREATEST(1, NULLIF(LENGTH(RP.Title) - LENGTH(REPLACE(RP.Title, ' ', '')),0) )))
    END AS ShortTitle
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RP.OwnerUserId,
    BC.BadgeCount,
    CS.CommentCount,
    CS.MaxCommentScore
ORDER BY 
    RP.Rank, RP.Score DESC;