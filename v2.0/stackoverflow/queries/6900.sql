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
        U.AccountId,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0 AND P.ViewCount > 0
),
BadgeCounts AS (
    SELECT 
        B.UserId,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Badges B
    GROUP BY 
        B.UserId
),
CommentStats AS (
    SELECT 
        PC.Id AS PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore,
        MIN(C.Score) AS MinCommentScore
    FROM 
        Posts PC
    LEFT JOIN 
        Comments C ON PC.Id = C.PostId
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
    RP.Rank,
    RC.BadgeCount,
    CS.CommentCount,
    CS.MaxCommentScore,
    CS.MinCommentScore,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    -- Extract first word robustly using standard SQL functions
    CASE
      WHEN POSITION(' ' IN RP.Title) = 0 THEN RP.Title
      ELSE SUBSTRING(RP.Title FROM 1 FOR POSITION(' ' IN RP.Title)-1)
    END AS FirstWord,
    CASE 
        WHEN RP.ViewCount > 1000 THEN CAST(RP.ViewCount AS VARCHAR) || 'K+'
        ELSE CAST(RP.ViewCount AS VARCHAR)
    END AS ViewCountFormatted
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts RC ON RP.AccountId = RC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
ORDER BY 
    ScoreTier DESC, RP.Rank ASC;