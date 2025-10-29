-- {"query": "6560.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 553} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank_score,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.ViewCount DESC, P.Score DESC) AS rank_views
    FROM Posts P
    JOIN Users U ON P.OwnerUserId = U.Id
    WHERE P.PostTypeId != 3 AND P.PostTypeId != 4 AND P.PostTypeId != 5
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
CommentedPosts AS (
    SELECT 
        P.Id AS PostId,
        COUNT(C.Id) AS CommentCount
    FROM Posts P
    JOIN Comments C ON P.Id = C.PostId
    GROUP BY P.Id
)
SELECT 
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank_score,
    RP.rank_views,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    COALESCE(CP.CommentCount, 0) AS CommentCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Regular'
    END AS PostType,
    LAG(RP.Score) OVER (ORDER BY RP.rank_score) AS PrevScore,
    LEAD(RP.Score) OVER (ORDER BY RP.rank_score) AS NextScore,
    U.Reputation,
    U.DisplayName,
    U.LastAccessDate
FROM RankedPosts RP
LEFT JOIN BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN CommentedPosts CP ON RP.Id = CP.PostId
JOIN Users U ON RP.OwnerUserId = U.Id
WHERE RP.rank_score <= 10 OR RP.rank_views <= 10
ORDER BY RP.rank_score, RP.rank_views;
