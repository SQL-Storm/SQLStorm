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
    WHERE 
        B.Class = 1 AND B.TagBased = FALSE
    GROUP BY 
        U.Id
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    RP.OwnerUserId,
    U.DisplayName,
    U.Reputation,
    COALESCE(BCount.BadgeCount, 0) AS BadgeCount,
    CASE 
        WHEN RP.rank <= 3 THEN 'Top'
        WHEN RP.rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankStatus,
    -- emulating SUBSTRING_INDEX for more portable SQL: take last two words then the first of those
    CASE
        WHEN RP.Title IS NULL THEN NULL
        ELSE
            SPLIT_PART(
                RP.Title,
                ' ',
                CASE
                    WHEN array_length(string_to_array(RP.Title, ' '), 1) >= 2
                    THEN array_length(string_to_array(RP.Title, ' '), 1) - 1
                    ELSE 1
                END
            )
    END AS ShortTitle
FROM 
    RankedPosts RP
JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts BCount ON RP.OwnerUserId = BCount.UserId
WHERE 
    RP.rank <= 10
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    RP.OwnerUserId,
    U.DisplayName,
    U.Reputation,
    BCount.BadgeCount
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;