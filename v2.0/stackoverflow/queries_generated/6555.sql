-- {"query": "6555.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 464} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        U.LastAccessDate,
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
        U.Reputation,
        COUNT(B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
RecentVotes AS (
    SELECT 
        V.PostId,
        V.UserId,
        V.VoteTypeId,
        V.CreationDate
    FROM 
        Votes V
    WHERE 
        V.CreationDate >= NOW() - INTERVAL '1 month'
)
SELECT 
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.Rank,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    COUNT(DISTINCT RV.UserId) AS RecentVoters,
    AVG(EXTRACT(EPOCH FROM RP.LastActivityDate - RP.CreationDate) / 3600) AS AvgHoursPerActivity
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    RecentVotes RV ON RP.Id = RV.PostId
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.Rank, BC.BadgeCount
ORDER BY 
    RP.Rank, RP.Score DESC;
