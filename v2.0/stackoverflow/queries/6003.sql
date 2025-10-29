WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
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
        V.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 month')
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    U.DisplayName,
    U.Reputation,
    B.BadgeCount,
    COUNT(DISTINCT RV.UserId) AS RecentVoters,
    SUM(CASE WHEN RV.VoteType = 'Positive' THEN 1 ELSE 0 END) AS PositiveVotes,
    SUM(CASE WHEN RV.VoteType = 'Negative' THEN 1 ELSE 0 END) AS NegativeVotes
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts B ON RP.OwnerUserId = B.UserId
LEFT JOIN 
    RecentVotes RV ON RP.Id = RV.PostId
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.Rank, RP.OwnerUserId, U.DisplayName, U.Reputation, B.BadgeCount
ORDER BY 
    RP.Rank, RP.Score DESC;