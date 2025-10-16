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
)
SELECT 
    R.Id,
    R.Title,
    R.Score,
    R.ViewCount,
    R.CreationDate,
    R.DisplayName,
    R.Reputation,
    R.rank,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CASE 
        WHEN R.Score > 100 THEN 'High'
        WHEN R.Score > 50 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    -- Use standard SQL to get the first word of the title
    CASE
      WHEN POSITION(' ' IN R.Title) > 0 THEN SUBSTRING(R.Title FROM 1 FOR POSITION(' ' IN R.Title) - 1)
      ELSE R.Title
    END AS TitleSnippet
FROM 
    RankedPosts R
LEFT JOIN 
    BadgeCounts BC ON R.OwnerUserId = BC.UserId
GROUP BY
    R.Id,
    R.Title,
    R.Score,
    R.ViewCount,
    R.CreationDate,
    R.OwnerUserId,
    R.DisplayName,
    R.Reputation,
    R.rank,
    BC.BadgeCount
ORDER BY 
    R.rank, R.Score DESC, R.ViewCount DESC
FETCH FIRST 100 ROWS ONLY;