-- {"query": "10055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 513} 

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
        U.AboutMe,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) -- Questions and Answers
        AND P.Score > 0
        AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        COUNT(B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
CommentStats AS (
    SELECT 
        P.Id AS PostId,
        COUNT(C.Id) AS CommentCount,
        SUM(C.Score) AS TotalCommentScore
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
    RP.OwnerDisplayName,
    RP.Reputation,
    RP.Location,
    RP.AboutMe,
    RP.Rank,
    CS.CommentCount,
    CS.TotalCommentScore,
    BC.DisplayName AS UserName,
    BC.Reputation AS UserReputation,
    BC.BadgeCount
FROM 
    RankedPosts RP
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerDisplayName = BC.DisplayName
WHERE 
    RP.Rank <= 10
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC
LIMIT 100;
