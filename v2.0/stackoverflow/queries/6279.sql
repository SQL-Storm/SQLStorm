-- {"query": "6279.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 521}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
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
        U.DisplayName, 
        COUNT(B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
CommentStats AS (
    SELECT 
        P.Id AS PostId, 
        COUNT(C.Id) AS CommentCount
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
    RP.rank,
    RP.DisplayName,
    RP.Reputation,
    COALESCE(CS.CommentCount, 0) AS CommentCount,
    COALESCE(B.BadgeCount, 0) AS BadgeCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    STRING_AGG(T.TagName, ', ' ORDER BY T.TagName) AS Tags
FROM 
    RankedPosts RP
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
LEFT JOIN 
    BadgeCounts B ON RP.DisplayName = B.DisplayName
LEFT JOIN 
    Posts P ON RP.Id = P.Id
LEFT JOIN 
    Tags T ON P.Id = T.ExcerptPostId
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.rank, RP.DisplayName, RP.Reputation, CS.CommentCount, B.BadgeCount
ORDER BY 
    RP.rank, RP.Score DESC;