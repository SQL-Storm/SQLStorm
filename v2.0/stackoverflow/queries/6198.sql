-- {"query": "6198.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 570}
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
        P.PostTypeId IN (1, 2) AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        B.UserId,
        COUNT(B.Id) AS BadgeCount
    FROM 
        Badges B
    GROUP BY 
        B.UserId
),
CommentStats AS (
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
    RP.Rank,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.OwnerDisplayName,
    RP.Reputation,
    RP.AccountId,
    BC.BadgeCount,
    CS.CommentCount,
    COALESCE(MAX(CS.MaxCommentScore), 0) AS MaxCommentScore,
    STRING_AGG(CASE WHEN PL.LinkTypeId = 3 THEN P2.Title ELSE NULL END, ', ' ORDER BY PL.CreationDate) AS DuplicateTitles
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.AccountId = BC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
LEFT JOIN 
    PostLinks PL ON RP.Id = PL.PostId
LEFT JOIN 
    Posts P2 ON PL.RelatedPostId = P2.Id AND PL.LinkTypeId = 3
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.Rank, RP.CreationDate, RP.LastActivityDate, RP.OwnerDisplayName, RP.Reputation, RP.AccountId, BC.BadgeCount, CS.CommentCount
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;