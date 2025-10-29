-- {"query": "6853.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 662} 

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
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        B.Class = 1 AND B.TagBased = FALSE
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
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    (SELECT COUNT(*) FROM Votes WHERE PostId = RP.Id AND VoteTypeId IN (2, 3)) AS VoteDiff,
    (SELECT SUM(Score) FROM Votes WHERE PostId = RP.Id AND VoteTypeId IN (2)) AS TotalUpVotes,
    (SELECT SUM(Score) FROM Votes WHERE PostId = RP.Id AND VoteTypeId IN (3)) AS TotalDownVotes,
    (SELECT DisplayName FROM Users WHERE Id = (SELECT TOP 1 UserId FROM Votes WHERE PostId = RP.Id AND VoteTypeId = 2 ORDER BY CreationDate DESC)) AS LastUpVoter,
    (SELECT COUNT(*) FROM PostLinks WHERE PostId = RP.Id AND LinkTypeId = 3) AS DuplicateCount,
    (SELECT MAX(CreationDate) FROM PostHistory WHERE PostId = RP.Id AND PostHistoryTypeId = 10) AS LastClosedDate,
    (SELECT Text FROM PostHistory WHERE PostId = RP.Id AND PostHistoryTypeId = 10 ORDER BY CreationDate DESC LIMIT 1) AS LastCloseReason,
    CM.CommentCount,
    CM.MaxCommentScore
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerDisplayName = BC.DisplayName
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
ORDER BY 
    RP.Rank;
