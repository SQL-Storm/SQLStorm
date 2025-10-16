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
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank,
        P.Tags
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
    -- split Tags string into rows; standard SQL: use a recursive split for portability
    SELECT
        RP.Id AS PostId,
        TRIM(tag) AS TagName,
        ROW_NUMBER() OVER (PARTITION BY RP.Id ORDER BY (SELECT 1)) AS TagIndex
    FROM RankedPosts RP,
    LATERAL (
        SELECT regexp_split_to_table(RP.Tags, E',<|>,<|>,') AS tag
    ) split
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
    BC.BadgeCount,
    CASE
        WHEN RP.Rank <= 3 THEN 'Top'
        WHEN RP.Rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankCategory,
    STRING_AGG(TG.TagName, ', ' ORDER BY TagCount DESC) AS TagList
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerDisplayName = U.DisplayName
LEFT JOIN 
    PostHistory PH ON RP.Id = PH.PostId AND PH.PostHistoryTypeId = 1
LEFT JOIN 
    PostTags TG ON RP.Id = TG.PostId
LEFT JOIN 
    (
        SELECT TagName, COUNT(*) AS TagCount
        FROM PostTags
        GROUP BY TagName
    ) TagCounts ON TG.TagName = TagCounts.TagName
LEFT JOIN 
    Tags T ON TG.TagName = T.TagName
LEFT JOIN 
    BadgeCounts BC ON U.Id = BC.UserId
WHERE 
    RP.Rank <= 10
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.Rank, U.DisplayName, U.Reputation, BC.BadgeCount
ORDER BY 
    RP.Rank;