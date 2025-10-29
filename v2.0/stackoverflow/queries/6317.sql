-- {"query": "6317.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 406}
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
        COUNT(B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
),
VoteCounts AS (
    SELECT
        V.PostId,
        COUNT(*) FILTER (WHERE V.UserId IS NOT NULL) AS TotalDistinctUserVotesApprox,
        COUNT(DISTINCT V.UserId) AS DistinctUserCount -- keep here for dialects that support it
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
    RP.LastActivityDate,
    RP.Rank,
    RP.OwnerDisplayName,
    RP.Reputation,
    BC.BadgeCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High Scoring'
        WHEN RP.ViewCount > 1000 THEN 'High Traffic'
        ELSE 'Regular'
    END AS PostType,
    COALESCE(VC.DistinctUserCount, VC.TotalDistinctUserVotesApprox, 0) AS TotalVotes
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerDisplayName = (SELECT DisplayName FROM Users U2 WHERE U2.Id = BC.UserId)
LEFT JOIN 
    VoteCounts VC ON RP.Id = VC.PostId
WHERE 
    RP.Rank <= 10
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RP.OwnerDisplayName,
    RP.Reputation,
    BC.BadgeCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High Scoring'
        WHEN RP.ViewCount > 1000 THEN 'High Traffic'
        ELSE 'Regular'
    END,
    VC.DistinctUserCount,
    VC.TotalDistinctUserVotesApprox
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;