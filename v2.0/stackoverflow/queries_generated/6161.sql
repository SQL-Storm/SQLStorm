-- {"query": "6161.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 465} 

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
        U.Id,
        U.DisplayName,
        COUNT(B.Id) AS badge_count
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
VotesSummary AS (
    SELECT 
        V.PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
    FROM 
        Votes V
    GROUP BY 
        V.PostId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    COALESCE(RS.upvotes, 0) AS total_upvotes,
    COALESCE(RS.downvotes, 0) AS total_downvotes,
    B.badge_count,
    U.Reputation,
    U.DisplayName,
    P.TagName,
    P.Count
FROM 
    RankedPosts RP
LEFT JOIN 
    VotesSummary RS ON RP.Id = RS.PostId
LEFT JOIN 
    BadgeCounts B ON RP.OwnerUserId = B.Id
LEFT JOIN 
    Tags P ON RP.Id = P.ExcerptPostId
WHERE 
    RP.rank <= 10
ORDER BY 
    RP.rank, RP.Score DESC;
