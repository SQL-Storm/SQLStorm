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
        B.Class = 1 AND B.TagBased = TRUE
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
    B.BadgeCount,
    CS.CommentCount,
    COALESCE(CS.MaxCommentScore, 0) AS MaxCommentScore,
    U.Reputation AS OwnerReputation,
    U.DisplayName AS OwnerDisplayName,
    COALESCE(NULLIF(
        -- emulate SUBSTRING_INDEX(..., ' ', -2) then take first word of that result
        (regexp_split_to_array(RP.Title, '\s+'))[greatest(array_length(regexp_split_to_array(RP.Title, '\s+'),1)-1,1)],
        ''
    ), '') AS TagName,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score > 50 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts B ON RP.OwnerDisplayName = B.DisplayName
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
JOIN 
    Users U ON RP.OwnerDisplayName = U.DisplayName
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    B.BadgeCount,
    CS.CommentCount,
    CS.MaxCommentScore,
    U.Reputation,
    U.DisplayName
ORDER BY 
    RP.Rank, RP.Score DESC;