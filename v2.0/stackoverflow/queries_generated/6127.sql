-- {"query": "6127.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 493} 

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
    WHERE P.PostTypeId IN (1, 2)
        AND P.Score > 0
        AND P.ViewCount > 100
        AND P.LastActivityDate > (CURRENT_TIMESTAMP - INTERVAL '1 month')
),
BadgeCounts AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(B.Id) AS BadgeCount
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE B.Class = 1
    GROUP BY U.Id, U.DisplayName
),
CommentMetrics AS (
    SELECT 
        PC.PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore,
        MIN(C.Score) AS MinCommentScore
    FROM Posts PC
    LEFT JOIN Comments C ON PC.Id = C.PostId
    GROUP BY PC.PostId
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
    CM.CommentCount,
    COALESCE(CM.MaxCommentScore, 0) AS MaxCommentScore,
    COALESCE(CM.MinCommentScore, 0) AS MinCommentScore
FROM RankedPosts RP
LEFT JOIN BadgeCounts BC ON RP.OwnerDisplayName = BC.DisplayName
LEFT JOIN CommentMetrics CM ON RP.Id = CM.PostId
WHERE RP.Rank <= 10
ORDER BY RP.Score DESC, RP.ViewCount DESC;
