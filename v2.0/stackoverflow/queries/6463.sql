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
        P.PostTypeId IN (1, 2) AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        B.UserId,
        COUNT(B.Id) AS BadgeCount
    FROM 
        Badges B
    GROUP BY 
        B.UserId
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
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Regular'
    END AS PopularityLevel,
    -- replace MySQL SUBSTRING_INDEX with standard SQL expression to get first word
    CASE 
      WHEN POSITION(' ' IN RP.Title) > 0 THEN SUBSTRING(RP.Title FROM 1 FOR POSITION(' ' IN RP.Title) - 1)
      ELSE RP.Title
    END AS FirstWord,
    CASE 
        WHEN RP.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAverage'
        ELSE 'BelowAverage'
    END AS ScoreLevel
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerDisplayName = CAST(BC.UserId AS VARCHAR)
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
    BC.BadgeCount,
    CS.CommentCount,
    CS.MaxCommentScore,
    RP.OwnerDisplayName
ORDER BY 
    RP.Rank, RP.Score DESC;