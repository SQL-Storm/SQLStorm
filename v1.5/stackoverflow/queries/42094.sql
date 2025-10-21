-- {"query": "42094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 744} 
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 2) OVER (PARTITION BY P.Id) AS UpVotes,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 3) OVER (PARTITION BY P.Id) AS DownVotes,
        COUNT(C.Id) OVER (PARTITION BY P.Id) AS CommentCount
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
),
TopUsers AS (
    SELECT 
        U.Id,
        U.Reputation,
        U.CreationDate,
        U.DisplayName,
        COUNT(B.Id) FILTER (WHERE B.Class = 1) AS GoldBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 2) AS SilverBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 3) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, U.CreationDate) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.Reputation, U.CreationDate, U.DisplayName
),
PostHistoryStats AS (
    SELECT 
        PH.PostId,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (7, 8, 9)) AS RollbackCount,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (10, 11)) AS CloseReopenCount
    FROM 
        PostHistory PH
    GROUP BY 
        PH.PostId
)
SELECT 
    RP.Id AS PostId,
    RP.PostTypeId,
    RP.CreationDate AS PostCreationDate,
    RP.Score,
    RP.ViewCount,
    RP.OwnerUserId,
    TU.Id AS UserId,
    TU.DisplayName,
    TU.Reputation,
    TU.GoldBadges,
    TU.SilverBadges,
    TU.BronzeBadges,
    RP.PostRank,
    RP.UpVotes,
    RP.DownVotes,
    RP.CommentCount,
    PHS.EditCount,
    PHS.RollbackCount,
    PHS.CloseReopenCount
FROM 
    RankedPosts RP
JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.Id
LEFT JOIN 
    PostHistoryStats PHS ON RP.Id = PHS.PostId
WHERE 
    RP.PostRank <= 10
    AND TU.UserRank <= 10
ORDER BY 
    RP.Score DESC, 
    TU.Reputation DESC;