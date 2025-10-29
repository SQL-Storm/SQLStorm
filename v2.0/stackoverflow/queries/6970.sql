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
    CO.CommentCount,
    CO.MaxCommentScore,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    -- Standard SQL: take last two words and then the first of those -> implemented with string functions
    TRIM(
      SUBSTRING(
        RP.Title
        FROM
          CASE
            WHEN POSITION(' ' IN REVERSE(RP.Title)) = 0 THEN 1
            ELSE
              -- find start of last two words: position of the second-to-last space from the end
              (CASE
                 WHEN POSITION(' ' IN RP.Title) = 0 THEN 1
                 ELSE GREATEST(
                   LENGTH(RP.Title) - NULLIF(NULLIF(POSITION(' ' IN REVERSE(RP.Title)),0),0) - 
                   (COALESCE(NULLIF(POSITION(' ' IN REVERSE(SUBSTRING(RP.Title FROM 1 FOR (LENGTH(RP.Title) - POSITION(' ' IN REVERSE(RP.Title)))))),0),0)) + 1,
                   1
                 )
               END)
          END
      )
    ) AS ShortTitle
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerDisplayName = BC.DisplayName
LEFT JOIN 
    CommentMetrics CO ON RP.Id = CO.PostId
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    BC.BadgeCount,
    CO.CommentCount,
    CO.MaxCommentScore,
    RP.OwnerDisplayName
ORDER BY 
    RP.Rank, RP.Score DESC;