WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.PostTypeId,
        P.OwnerUserId AS UserId,
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
    RP.LastActivityDate,
    RP.PostTypeId,
    RP.rank,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    -- portable way to get the second-to-last word: take words array behavior using standard SQL functions where available.
    -- Using regexp to emulate SUBSTRING_INDEX: get penultimate word if title has at least 2 words, else the first word.
    COALESCE(
      NULLIF(REGEXP_REPLACE(RP.Title, '^.*\\s+(\\S+)\\s+(\\S+)$', '\\1'), RP.Title),
      NULLIF(REGEXP_REPLACE(RP.Title, '^.*\\s+(\\S+)$', '\\1'), RP.Title),
      RP.Title
    ) AS ShortTitle,
    U.DisplayName,
    U.Reputation,
    CASE 
        WHEN RP.rank <= 3 THEN 'Top'
        ELSE 'Other'
    END AS PostRank
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.UserId = BC.UserId
JOIN 
    Users U ON RP.UserId = U.Id
ORDER BY 
    RP.PostTypeId, RP.rank, RP.Score DESC;