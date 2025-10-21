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
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.LastActivityDate DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 0
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
CommentMetrics AS (
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
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RP.OwnerDisplayName,
    RP.Reputation,
    BC.BadgeCount,
    COALESCE(CM.CommentCount, 0) AS CommentCount,
    CM.MaxCommentScore,
    CM.MinCommentScore,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score > 50 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    TRIM(
        SUBSTRING(
            RP.Title FROM
            GREATEST(1, LENGTH(RP.Title) - LENGTH(REVERSE(RP.Title)) - 
                LENGTH(SUBSTRING(REVERSE(RP.Title) FROM 1 FOR POSITION(' ' IN REVERSE(RP.Title)) - 1)))
            FOR 1000
        )
    ) AS ShortTitle
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerDisplayName = BC.DisplayName
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
ORDER BY 
    RP.Rank, RP.Score DESC;