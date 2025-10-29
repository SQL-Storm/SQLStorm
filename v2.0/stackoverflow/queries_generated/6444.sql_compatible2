WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        P.PostTypeId,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank_score,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.ViewCount DESC, P.Score DESC) AS rank_views
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0 AND P.ViewCount > 0
),
BadgeCounts AS (
    SELECT 
        UserId,
        COUNT(DISTINCT Id) AS badge_count
    FROM 
        Badges
    GROUP BY 
        UserId
),
PostTags AS (
    -- split tags stored like '<tag1><tag2>' or similar into rows
    SELECT
        P.Id AS PostId,
        TRIM(BOTH '<>' FROM tag) AS TagName
    FROM
        Posts P,
        LATERAL (
            SELECT regexp_split_to_table(P.Tags, '><') AS tag
        ) s
    WHERE P.Tags IS NOT NULL
),
TagAgg AS (
    -- aggregate tags per post with counts and ordered list
    SELECT
        PT.PostId,
        STRING_AGG(PT.TagName, ', ' ORDER BY tag_count DESC, PT.TagName) AS tag_list,
        SUM(tag_count) AS tag_count
    FROM (
        SELECT PostId, TagName, COUNT(*) AS tag_count
        FROM PostTags
        GROUP BY PostId, TagName
    ) PT
    GROUP BY PT.PostId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    BC.badge_count,
    CASE 
        WHEN RP.rank_score <= 3 THEN 'Top Score'
        WHEN RP.rank_views <= 3 THEN 'Top Views'
        ELSE 'Regular'
    END AS rank,
    TA.tag_list,
    TA.tag_count
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    Posts P ON RP.Id = P.Id
LEFT JOIN 
    TagAgg TA ON RP.Id = TA.PostId
WHERE
    RP.PostTypeId = 1
GROUP BY 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    BC.badge_count,
    RP.rank_score,
    RP.rank_views,
    TA.tag_list,
    TA.tag_count
HAVING 
    COALESCE(TA.tag_count, 0) > 2
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC
LIMIT 100;