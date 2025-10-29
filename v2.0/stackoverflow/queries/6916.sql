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
        V.CreationDate,
        V.VoteTypeId,
        CASE 
            WHEN V.VoteTypeId IN (2, 8, 9) THEN 'Positive'
            WHEN V.VoteTypeId IN (3, 12) THEN 'Negative'
            ELSE 'Neutral'
        END AS VoteType
    FROM 
        Votes V
    WHERE 
        V.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 month')
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RP.DisplayName,
    RP.Reputation,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    RV.PostId AS VotedPost,
    RV.UserId AS VoterId,
    RV.CreationDate AS VoteDate,
    RV.VoteType
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
    RP.OwnerUserId,
    RP.DisplayName,
    RP.Reputation,
    RP.Rank,
    BC.BadgeCount,
    RV.PostId,
    RV.UserId,
    RV.CreationDate,
    RV.VoteType
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC
LIMIT 100;