WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName,
        U.Reputation,
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
    SELECT
        P.Id AS PostId,
        TRIM(BOTH '<' FROM t.tag) AS TagName
    FROM Posts P
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(replace(replace(P.Tags, '><', '>|<'), '><', '>|<'), '|')) AS tag
    ) t
    WHERE P.Tags IS NOT NULL AND P.Tags <> ''
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.rank,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium'
        WHEN RP.Score <= 50 THEN 'Low'
    END AS ScoreTier,
    STRING_AGG(TT.TagName, ', ' ORDER BY TagCount DESC, TT.TagName) AS TagList
FROM 
    RankedPosts RP
LEFT JOIN 
    (
      SELECT PostId, TagName, COUNT(*) AS TagCount
      FROM PostTags
      GROUP BY PostId, TagName
    ) TT ON TT.PostId = RP.Id
LEFT JOIN 
    Tags T ON T.TagName = TT.TagName
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
WHERE 
    RP.rank <= 10
    AND RP.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.DisplayName, RP.Reputation, RP.rank, BC.BadgeCount
ORDER BY 
    RP.Score DESC, RP.rank ASC;