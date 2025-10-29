-- {"query": "6941.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 467} 
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
        P.PostTypeId = 1 AND P.LastActivityDate > P.CreationDate
),
BadgeCounts AS (
    SELECT 
        B.UserId,
        U.DisplayName,
        COUNT(B.Id) AS BadgeCount
    FROM 
        Badges B
    JOIN 
        Users U ON B.UserId = U.Id
    WHERE 
        B.Class = 1 AND B.TagBased = FALSE
    GROUP BY 
        B.UserId, U.DisplayName
),
CommentScores AS (
    SELECT 
        C.PostId,
        AVG(C.Score) AS AvgCommentScore
    FROM 
        Comments C
    GROUP BY 
        C.PostId
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
    RC.BadgeCount,
    COALESCE(CS.AvgCommentScore, 0) AS AvgCommentScore,
    CASE 
        WHEN RP.Rank <= 3 THEN 'Top'
        WHEN RP.Rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankStatus
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts RC ON RP.OwnerDisplayName = RC.DisplayName
LEFT JOIN 
    CommentScores CS ON RP.Id = CS.PostId
WHERE 
    RP.Rank <= 10 AND RP.Score > 0 AND RP.ViewCount >= 100
ORDER BY 
    RP.Rank, RP.Score DESC;