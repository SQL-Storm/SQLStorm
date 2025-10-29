WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM Posts P
    JOIN Users U ON P.OwnerUserId = U.Id
    WHERE P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        B.UserId,
        COUNT(B.Id) AS BadgeCount
    FROM Badges B
    WHERE B.Class = 1 AND B.TagBased = FALSE
    GROUP BY B.UserId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RP.DisplayName,
    RP.Reputation,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High Scoring'
        WHEN RP.ViewCount > 1000 THEN 'High Traffic'
        ELSE 'Regular'
    END AS PostType,
    STRING_AGG(T.TagName, ', ' ORDER BY T.Count DESC) AS Tags
FROM RankedPosts RP
LEFT JOIN BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN Posts P ON RP.Id = P.Id
LEFT JOIN Tags T ON P.Id = T.ExcerptPostId
GROUP BY RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.Rank, RP.DisplayName, RP.Reputation, BC.BadgeCount, RP.OwnerUserId
ORDER BY RP.Rank, RP.Score DESC;