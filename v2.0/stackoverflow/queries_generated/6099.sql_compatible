WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName,
        U.Reputation,
        U.LastAccessDate,
        P.OwnerUserId,
        ROW_NUMBER() OVER (ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    JOIN 
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
    RP.DisplayName,
    RP.Reputation,
    RP.LastAccessDate,
    RP.Rank,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CASE 
        WHEN RP.Score > (SELECT AVG(CAST(Score AS NUMERIC)) FROM Posts WHERE PostTypeId = 1) THEN 'High Scoring'
        ELSE 'Average Scoring'
    END AS ScoreTier,
    CASE 
        WHEN RP.ViewCount > (SELECT AVG(CAST(ViewCount AS NUMERIC)) FROM Posts WHERE PostTypeId = 1) THEN 'High Viewed'
        ELSE 'Average Viewed'
    END AS ViewTier
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
WHERE 
    EXISTS (
        SELECT 1
        FROM PostHistory PH
        WHERE PH.PostId = RP.Id AND PH.PostHistoryTypeId = 10
    )
ORDER BY 
    RP.Rank;