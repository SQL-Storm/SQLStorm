WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId NOT IN (3,4,5,6,7,8)
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
HighReputationUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        MAX(U.LastAccessDate) AS last_access
    FROM 
        Users U
    WHERE 
        U.Reputation > 10000
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
RecentVotes AS (
    SELECT 
        V.PostId,
        V.VoteTypeId,
        V.CreationDate
    FROM 
        Votes V
    WHERE 
        V.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 month')
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    COALESCE(BC.badge_count, 0) AS badge_count,
    HRU.DisplayName AS high_reputation_user,
    HRU.last_access,
    COUNT(RV.PostId) AS recent_votes
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.Id
LEFT JOIN 
    HighReputationUsers HRU ON RP.OwnerUserId = HRU.Id
LEFT JOIN 
    RecentVotes RV ON RP.Id = RV.PostId
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.rank, RP.OwnerUserId, BC.badge_count, HRU.DisplayName, HRU.last_access
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC
LIMIT 100;