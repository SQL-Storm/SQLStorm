WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        U.DisplayName,
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
        COUNT(B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
RecentVotes AS (
    SELECT 
        V.PostId,
        V.UserId,
        COUNT(V.Id) AS VoteCount,
        MAX(V.CreationDate) AS LastVoteDate
    FROM 
        Votes V
    WHERE 
        V.VoteTypeId IN (2, 3) AND V.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 month')
    GROUP BY 
        V.PostId, V.UserId
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
    ROW_NUMBER() OVER (ORDER BY RP.Score DESC, RP.ViewCount DESC) AS GlobalRank,
    RV.VoteCount,
    RV.LastVoteDate,
    CASE 
        WHEN RP.Score > 100 THEN 'High Scoring'
        WHEN RP.ViewCount > 1000 THEN 'High Viewed'
        ELSE 'Regular'
    END AS Popularity,
    CASE
        WHEN RP.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 week') THEN 'Active'
        ELSE 'Inactive'
    END AS ActivityStatus,
    RP.OwnerUserId,
    RP.DisplayName,
    RP.Reputation
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    RecentVotes RV ON RP.Id = RV.PostId
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    BC.BadgeCount,
    RV.VoteCount,
    RV.LastVoteDate,
    RP.OwnerUserId,
    RP.DisplayName,
    RP.Reputation
ORDER BY 
    RP.Rank, RP.Score DESC, RP.ViewCount DESC;