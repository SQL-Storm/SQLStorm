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
    CASE
      WHEN RP.Title IS NULL OR RP.Title = '' THEN ''
      ELSE (
        SELECT COALESCE(NULLIF(word, ''), '')
        FROM (
          SELECT
            trim(word) AS word,
            row_number() OVER (ORDER BY (SELECT NULL)) AS rn,
            (SELECT count(*) FROM (
                SELECT trim(value) AS v FROM (
                    -- split title by spaces using standard string functions
                    SELECT regexp_split_to_table(
                        replace(replace(RP.Title, '"', '\"'), E'\\s+', ' '),
                        ' '
                    ) AS value
                ) AS split_inner
            ) AS cnt) AS total_words
          FROM (
            SELECT regexp_split_to_table(replace(replace(RP.Title, '"', '\"'), E'\\s+', ' '), ' ') AS word
          ) s
        ) t
        WHERE rn = total_words - 1
        LIMIT 1
      )
    END AS ShortTitle
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerDisplayName = BC.DisplayName
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
ORDER BY 
    RP.Rank, RP.Score DESC;