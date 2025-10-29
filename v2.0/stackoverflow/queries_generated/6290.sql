-- {"query": "6290.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 761} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        U.Reputation,
        U.Location,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        B.UserId,
        COUNT(B.Id) AS BadgeCount,
        MAX(CASE WHEN B.TagBased THEN 'Tag' ELSE 'Named' END) AS BadgeType
    FROM 
        Badges B
    GROUP BY 
        B.UserId
),
CommentStats AS (
    SELECT 
        P.Id AS PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore,
        MIN(C.CreationDate) AS EarliestCommentDate
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
    BC.BadgeCount,
    BC.BadgeType,
    COALESCE(CS.CommentCount, 0) AS CommentCount,
    COALESCE(MAX(CASE WHEN CS.CommentCount > 0 THEN CS.MaxCommentScore ELSE NULL END), 0) AS MaxCommentScore,
    COALESCE(MIN(CASE WHEN CS.CommentCount > 0 THEN CS.EarliestCommentDate ELSE NULL END), '1900-01-01') AS EarliestCommentDate,
    COUNT(DISTINCT V.UserId) AS DistinctVoters,
    SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN V.VoteTypeId IN (8, 9) THEN V.BountyAmount ELSE 0 END) AS TotalBounty
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
LEFT JOIN 
    Votes V ON RP.Id = V.PostId
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.OwnerDisplayName, RP.Reputation, RP.Location, BC.BadgeCount, BC.BadgeType, CS.CommentCount, CS.MaxCommentScore, CS.EarliestCommentDate
HAVING 
    SUM(CASE WHEN V.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) > 10
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;
