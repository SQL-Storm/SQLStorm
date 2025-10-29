WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        P.OwnerUserId,
        P.Tags,
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
    BC.BadgeCount,
    CASE
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score > 50 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    (
        SELECT 
            STRING_AGG(T.TagName, ', ')
        FROM 
            (
                SELECT TRIM(BOTH '<>' FROM x) AS tagstr
                FROM (
                    -- split tags like '<tag1><tag2>' into elements '<tag1' 'tag2>' then trim
                    SELECT UNNEST(STRING_TO_ARRAY(RP.Tags, '><')) AS x
                ) AS t
            ) AS tagrows
        JOIN 
            Tags T ON (CASE WHEN tagrows.tagstr ~ '^[0-9]+$' THEN CAST(tagrows.tagstr AS INTEGER) ELSE NULL END) = T.Id
    ) AS Tags
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
WHERE 
    RP.rank <= 10
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.rank,
    BC.BadgeCount,
    RP.OwnerUserId,
    RP.Tags
ORDER BY 
    RP.Score DESC, 
    RP.ViewCount DESC;