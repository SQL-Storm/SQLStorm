WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        P.OwnerUserId AS UserId,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
),
PostTags AS (
    -- Normalize Posts.Tags like "<tag1><tag2>" into one tag per row (portable SQL)
    SELECT
        P.Id AS PostId,
        TRIM(tag) AS Tag
    FROM
        Posts P,
        LATERAL (
            SELECT regexp_split_to_table(P.Tags, '><|^<|>$') AS tag
        ) s
    WHERE P.Tags IS NOT NULL AND P.Tags <> ''
),
TagCountsPerPost AS (
    SELECT
        PT.PostId,
        PT.Tag,
        COUNT(*) AS TagCount
    FROM PostTags PT
    GROUP BY PT.PostId, PT.Tag
),
TagListPerPost AS (
    SELECT
        TCP.PostId,
        STRING_AGG(TCP.Tag, ', ' ORDER BY TCP.TagCount DESC, TCP.Tag) AS TagList
    FROM TagCountsPerPost TCP
    GROUP BY TCP.PostId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CASE 
        WHEN RP.rank <= 3 THEN 'Top'
        WHEN RP.rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankLevel,
    COALESCE(TLP.TagList, '') AS TagList
FROM 
    RankedPosts RP
LEFT JOIN 
    TagListPerPost TLP ON TLP.PostId = RP.Id
LEFT JOIN 
    BadgeCounts BC ON RP.UserId = BC.UserId
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.DisplayName, RP.Reputation, RP.rank, BC.BadgeCount, TLP.TagList
ORDER BY 
    RP.rank, RP.Score DESC;