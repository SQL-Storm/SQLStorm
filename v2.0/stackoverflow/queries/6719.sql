WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM Users U
    JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id
),
PostTags AS (
    SELECT
        P.Id AS PostId,
        TRIM(BOTH '<>' FROM UNNEST(string_to_array(P.Tags, '><'))) AS tag_text
    FROM Posts P
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    U.DisplayName,
    U.Reputation,
    BC.BadgeCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High Scoring'
        WHEN RP.ViewCount > 1000 THEN 'High Viewed'
        ELSE 'Regular'
    END AS PostStatus,
    (
        SELECT STRING_AGG(T.TagName, ', ')
        FROM PostTags PT
        JOIN Tags T ON PT.tag_text = T.TagName
        WHERE PT.PostId = RP.Id
    ) AS Tags
FROM 
    RankedPosts RP
JOIN 
    Users U ON RP.OwnerUserId = U.Id
JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN Posts P2 ON P2.Id = RP.Id
WHERE 
    RP.Rank <= 10
    AND U.Reputation > 100
    AND (RP.Score > 50 OR RP.ViewCount > 500)
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RP.OwnerUserId,
    U.DisplayName,
    U.Reputation,
    BC.BadgeCount,
    P2.Tags
ORDER BY 
    RP.Score DESC, RP.Rank ASC;