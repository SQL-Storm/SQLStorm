WITH RankedPosts AS (
    SELECT 
        P.Id, 
        P.PostTypeId, 
        P.CreationDate, 
        P.Score, 
        P.ViewCount, 
        P.OwnerUserId, 
        U.Reputation AS OwnerReputation,
        COUNT(C.Id) AS CommentCount,
        COUNT(V.Id) AS VoteCount,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.OwnerUserId, U.Reputation
),
TopUsers AS (
    SELECT 
        U.Id, 
        U.Reputation, 
        U.CreationDate, 
        U.DisplayName, 
        COUNT(B.Id) AS BadgeCount,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, U.CreationDate) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.Reputation, U.CreationDate, U.DisplayName
)
SELECT 
    RP.Id AS PostId, 
    RP.PostTypeId, 
    RP.CreationDate AS PostCreationDate, 
    RP.Score, 
    RP.ViewCount, 
    RP.OwnerUserId, 
    RP.OwnerReputation, 
    RP.CommentCount, 
    RP.VoteCount, 
    RP.PostRank, 
    TU.Id AS UserId, 
    TU.Reputation AS UserReputation, 
    TU.CreationDate AS UserCreationDate, 
    TU.DisplayName, 
    TU.BadgeCount, 
    TU.UserRank
FROM 
    RankedPosts RP
JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.Id
WHERE 
    RP.PostRank <= 100 AND TU.UserRank <= 100
ORDER BY 
    RP.PostRank, TU.UserRank;