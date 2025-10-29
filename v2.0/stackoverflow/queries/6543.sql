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
        PC.Id AS PostId,
        COUNT(C.Id) AS CommentCount,
        SUM(C.Score) AS TotalCommentScore
    FROM 
        Posts PC
    LEFT JOIN 
        Comments C ON PC.Id = C.PostId
    GROUP BY 
        PC.Id
),
PostTags AS (
    -- split tags stored like '<tag1><tag2>' or comma-separated; standardized splitting using SQL standard functions is dialect-specific.
    -- This implementation attempts to extract tags by removing angle brackets and splitting on '><' or comma.
    SELECT
        P.Id AS PostId,
        TRIM(tag) AS TagName
    FROM
        Posts P,
        LATERAL (
            SELECT value AS tag
            FROM (
                -- normalize delimiters to comma
                SELECT regexp_replace(
                    regexp_replace(P.Tags, '^<|>$', ''),            -- remove leading/trailing angle brackets
                    '><', ',' , 'g'                                  -- replace >< with ,
                ) AS tags_norm
            ) t,
            LATERAL (
                SELECT regexp_split_to_table(t.tags_norm, ',') AS value
            ) s
        ) split
    WHERE P.Tags IS NOT NULL AND P.Tags <> ''
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
    COALESCE(CM.CommentCount, 0) AS CommentCount,
    COALESCE(CM.TotalCommentScore, 0) AS TotalCommentScore,
    CASE 
        WHEN RP.Score > 100 THEN 'High Scoring'
        WHEN RP.ViewCount > 1000 THEN 'High Viewed'
        ELSE 'Regular'
    END AS PostStatus,
    STRING_AGG(DISTINCT PT.TagName, ', ') AS Tags
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerDisplayName = BC.DisplayName
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
LEFT JOIN 
    PostTags PT ON RP.Id = PT.PostId
LEFT JOIN 
    Tags TG ON PT.TagName = TG.TagName
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.Rank, BC.BadgeCount, CM.CommentCount, CM.TotalCommentScore
ORDER BY 
    RP.Rank, RP.Score DESC;