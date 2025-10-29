-- {"query": "6063.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 503}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        P.PostTypeId,
        P.AnswerCount,
        P.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank,
        P.OwnerUserId
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
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName AS OwnerDisplayName,
    RP.Reputation,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    COUNT(DISTINCT V.UserId) AS UpVotes,
    AVG(V.BountyAmount) AS AvgBounty,
    MAX(CASE WHEN RP.PostTypeId = 1 THEN RP.AnswerCount ELSE 0 END) AS AnswerCount,
    MAX(CASE WHEN RP.PostTypeId = 1 THEN CASE WHEN RP.ClosedDate IS NOT NULL THEN 1 ELSE 0 END ELSE 0 END) AS IsClosed,
    STRING_AGG(T.TagName, ', ' ORDER BY T.TagName) AS Tags
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId AND RP.Reputation > 1000
LEFT JOIN 
    Votes V ON RP.Id = V.PostId AND V.VoteTypeId = 2
LEFT JOIN 
    Posts P ON RP.Id = P.Id
LEFT JOIN 
    Tags T ON P.Id = T.ExcerptPostId
GROUP BY 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    BC.BadgeCount,
    RP.PostTypeId,
    RP.AnswerCount,
    RP.ClosedDate,
    RP.OwnerUserId,
    RP.rank
ORDER BY 
    RP.rank, RP.Score DESC;