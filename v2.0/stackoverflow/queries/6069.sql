-- {"query": "6069.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 590}
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
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
CommentMetrics AS (
    SELECT 
        P.Id AS PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore
    FROM 
        Posts P
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    GROUP BY 
        P.Id
)
SELECT 
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    U.DisplayName AS OwnerDisplayName,
    U.Reputation,
    U.AccountId,
    BG.BadgeCount,
    CM.CommentCount,
    COALESCE(CM.MaxCommentScore, 0) AS MaxCommentScore,
    (
      SELECT STRING_AGG(t.Title, ', ' ORDER BY t.Id)
      FROM (
        SELECT DISTINCT P2.Title, P2.Id
        FROM Posts P2
        WHERE P2.ParentId = RP.Id AND P2.PostTypeId = 3
      ) t
    ) AS WikiPostTitles
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerDisplayName = U.DisplayName
LEFT JOIN 
    BadgeCounts BG ON U.Id = BG.UserId
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
LEFT JOIN 
    Posts P ON RP.Id = P.ParentId AND P.PostTypeId = 3
WHERE 
    RP.Rank <= 10
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.Rank, U.DisplayName, U.Reputation, U.AccountId, BG.BadgeCount, CM.CommentCount, CM.MaxCommentScore
ORDER BY 
    RP.Rank;