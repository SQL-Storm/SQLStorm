WITH RankedPosts AS (
    SELECT 
        P.Id, 
        P.PostTypeId, 
        P.CreationDate, 
        P.Score, 
        P.ViewCount, 
        P.OwnerUserId, 
        U.Reputation, 
        U.DisplayName, 
        COUNT(V.Id) AS VoteCount,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.PostTypeId IN (1, 2) AND 
        P.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    GROUP BY 
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.OwnerUserId, U.Reputation, U.DisplayName
),
TopUsers AS (
    SELECT 
        U.Id, 
        U.DisplayName, 
        U.Reputation, 
        COUNT(B.Id) AS BadgeCount,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, U.CreationDate) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        U.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
)
SELECT 
    RP.Id AS PostId, 
    RP.PostTypeId, 
    RP.CreationDate AS PostCreationDate, 
    RP.Score, 
    RP.ViewCount, 
    RP.OwnerUserId, 
    TU.DisplayName AS OwnerDisplayName, 
    RP.Reputation, 
    RP.VoteCount, 
    RP.PostRank, 
    TU.BadgeCount, 
    TU.UserRank
FROM 
    RankedPosts RP
JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.Id
WHERE 
    RP.PostRank <= 10 AND 
    TU.UserRank <= 10
ORDER BY 
    RP.Score DESC, 
    TU.Reputation DESC;