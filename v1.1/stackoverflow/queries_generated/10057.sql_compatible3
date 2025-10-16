WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName AS Owner,
        U.Reputation,
        U.Location,
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
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Owner AS OwnerDisplayName,
    RP.Reputation,
    RP.Location,
    BC.BadgeCount,
    CASE 
        WHEN RP.Rank <= 3 THEN 'Top'
        WHEN RP.Rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankStatus,
    (
        SELECT 
            STRING_AGG(T.TagName, ', ')
        FROM 
            (
                SELECT CAST(t.tag AS INTEGER) AS tag_id
                FROM (
                    SELECT regexp_split_to_array(regexp_replace(COALESCE(RP_Tags.TagsText, ''), '^<|>$', '', 'g'), '><') AS arr
                ) AS split_source,
                UNNEST(split_source.arr) AS t(tag)
            ) AS TagArray
        JOIN 
            Tags T ON T.Id = TagArray.tag_id
    ) AS Tags
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON BC.UserId = CASE 
        WHEN RP.Owner ~ '^\d+$' THEN CAST(RP.Owner AS INTEGER)
        ELSE NULL
    END
LEFT JOIN (
    SELECT P2.Id AS PostId, COALESCE(P2.Tags, '') AS TagsText
    FROM Posts P2
) RP_Tags ON RP_Tags.PostId = RP.Id
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Owner,
    RP.Reputation,
    RP.Location,
    RP.Rank,
    BC.BadgeCount,
    RP_Tags.TagsText
ORDER BY 
    RP.Rank;