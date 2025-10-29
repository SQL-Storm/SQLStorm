-- {"query": "6674.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 601}
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
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 0
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT B.Id) AS BadgeCount,
        MAX(CASE WHEN B.Class = 1 THEN B.Date ELSE NULL END) AS GoldBadgeDate,
        MAX(CASE WHEN B.Class = 2 THEN B.Date ELSE NULL END) AS SilverBadgeDate,
        MAX(CASE WHEN B.Class = 3 THEN B.Date ELSE NULL END) AS BronzeBadgeDate
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    BC.GoldBadgeDate,
    BC.SilverBadgeDate,
    BC.BronzeBadgeDate,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score > 50 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    STRING_AGG(T.TagName, ', ' ORDER BY T.TagName) AS Tags
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerDisplayName = BC.DisplayName
LEFT JOIN 
    Posts P ON RP.Id = P.Id
LEFT JOIN LATERAL (
    SELECT TRIM(tag_val) AS TagName
    FROM (
        SELECT REGEXP_SPLIT_TO_TABLE(COALESCE(P.Tags, ''), ',') AS tag_val
    ) s
) AS T ON TRUE
WHERE 
    RP.Rank <= 10
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.Rank, BC.BadgeCount, BC.GoldBadgeDate, BC.SilverBadgeDate, BC.BronzeBadgeDate
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;