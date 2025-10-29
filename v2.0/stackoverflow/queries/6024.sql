-- {"query": "6024.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 564}
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
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
),
PostTags AS (
    SELECT
        PH.PostId,
        TRIM(tag) AS TagName
    FROM PostHistory PH
    CROSS JOIN LATERAL (
        SELECT
            regexp_split_to_table(
                substring(PH.Text FROM 13 FOR (char_length(PH.Text) - 13)),
                ','
            ) AS tag
    ) s
    WHERE PH.PostHistoryTypeId = 1
),
TagCounts AS (
    -- compute count per post/tag to allow ordering tags by frequency per post
    SELECT
        pt.PostId,
        pt.TagName,
        COUNT(*) AS TagCount
    FROM PostTags pt
    GROUP BY pt.PostId, pt.TagName
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    U.DisplayName AS OwnerDisplayName,
    U.Reputation,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CASE
        WHEN RP.Rank <= 3 THEN 'Top'
        WHEN RP.Rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankCategory,
    STRING_AGG(tc.TagName, ', ' ORDER BY tc.TagCount DESC, tc.TagName) AS TagList
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerDisplayName = U.DisplayName
LEFT JOIN 
    TagCounts tc ON RP.Id = tc.PostId
LEFT JOIN 
    Tags t ON tc.TagName = t.TagName
LEFT JOIN 
    BadgeCounts BC ON U.Id = BC.UserId
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.Rank, U.DisplayName, U.Reputation, BC.BadgeCount
ORDER BY 
    RP.Rank, RP.Score DESC;