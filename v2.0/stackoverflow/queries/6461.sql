-- {"query": "6461.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 453}
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
        U.LastAccessDate,
        ROW_NUMBER() OVER (ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1
        AND P.Score > 0
        AND P.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days')
),
BadgeCounts AS (
    SELECT 
        UserId,
        COUNT(DISTINCT Id) AS BadgeCount
    FROM 
        Badges
    WHERE 
        Class = 1
        AND TagBased = FALSE
    GROUP BY 
        UserId
),
CommentStats AS (
    SELECT 
        PostId,
        COUNT(Id) AS CommentCount,
        MAX(Score) AS MaxCommentScore
    FROM 
        Comments
    GROUP BY 
        PostId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RP.DisplayName,
    RP.Reputation,
    RP.LastAccessDate,
    BC.BadgeCount,
    CS.CommentCount,
    COALESCE(CS.MaxCommentScore, 0) AS MaxCommentScore,
    CASE 
        WHEN RP.Score > 100 AND RP.ViewCount > 1000 THEN 'High Visibility'
        WHEN RP.Score > 50 AND RP.ViewCount > 500 THEN 'Medium Visibility'
        ELSE 'Low Visibility'
    END AS VisibilityLevel
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
ORDER BY 
    RP.Rank;