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
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank_score,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.ViewCount DESC, P.Score DESC) AS rank_views
    FROM Posts P
    JOIN Users U ON P.OwnerUserId = U.Id
    WHERE P.PostTypeId IN (1, 2)
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM Users U
    JOIN Badges B ON U.Id = B.UserId
    WHERE B.Class = 1
    GROUP BY U.Id
),
CommentStats AS (
    SELECT 
        P.Id AS PostId,
        COUNT(C.Id) AS CommentCount
    FROM Posts P
    JOIN Comments C ON P.Id = C.PostId
    WHERE C.ContentLicense IS NOT NULL
    GROUP BY P.Id
)
SELECT 
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.rank_score,
    RP.rank_views,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    COALESCE(CS.CommentCount, 0) AS CommentCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Regular'
    END AS PostStatus
FROM RankedPosts RP
LEFT JOIN BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN CommentStats CS ON RP.Id = CS.PostId
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.rank_score,
    RP.rank_views,
    BC.BadgeCount,
    CS.CommentCount,
    RP.OwnerUserId
ORDER BY RP.rank_score, RP.rank_views;