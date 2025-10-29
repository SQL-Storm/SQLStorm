-- {"query": "6229.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 533} 

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
        U.AccountId,
        U.Location,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM Posts P
    LEFT JOIN Users U ON P.OwnerUserId = U.Id
    WHERE P.PostTypeId = 1 AND P.Score > 100 AND P.ViewCount > 1000
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(B.Id) AS BadgeCount,
        MAX(CASE WHEN B.Class = 1 THEN B.Date ELSE NULL END) AS GoldBadgeDate,
        MAX(CASE WHEN B.Class = 2 THEN B.Date ELSE NULL END) AS SilverBadgeDate,
        MAX(CASE WHEN B.Class = 3 THEN B.Date ELSE NULL END) AS BronzeBadgeDate
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE B.TagBased IS FALSE
    GROUP BY U.Id, U.DisplayName
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.OwnerDisplayName,
    RP.Reputation,
    RP.Location,
    RP.Rank,
    BC.BadgeCount,
    BC.GoldBadgeDate,
    BC.SilverBadgeDate,
    BC.BronzeBadgeDate,
    CASE 
        WHEN RP.Score > 1000 THEN 'High'
        WHEN RP.Score BETWEEN 500 AND 1000 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    CASE 
        WHEN RP.ViewCount > 10000 THEN 'Popular'
        WHEN RP.ViewCount BETWEEN 5000 AND 10000 THEN 'Moderate'
        ELSE 'Less Popular'
    END AS ViewTier
FROM RankedPosts RP
LEFT JOIN BadgeCounts BC ON RP.OwnerDisplayName = BC.DisplayName
ORDER BY RP.Rank, RP.Score DESC, RP.ViewCount DESC;
