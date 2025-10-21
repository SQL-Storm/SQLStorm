-- {"query": "12078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 895} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2)
),
TopUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, COUNT(B.Id) DESC) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
PostTagCounts AS (
    SELECT 
        P.Id,
        COUNT(T.Id) AS TagCount
    FROM 
        Posts P
    JOIN 
        Tags T ON P.Tags LIKE '%' || T.TagName || '%'
    GROUP BY 
        P.Id
),
PostComments AS (
    SELECT 
        C.PostId,
        COUNT(C.Id) AS CommentCount
    FROM 
        Comments C
    GROUP BY 
        C.PostId
),
PostVotes AS (
    SELECT 
        V.PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Votes V
    GROUP BY 
        V.PostId
),
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(DISTINCT PH.Id) AS TotalEdits,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditDate
    FROM 
        PostHistory PH
    GROUP BY 
        PH.PostId
)
SELECT 
    RP.Id AS PostId,
    RP.PostTypeId,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    RP.PostRank,
    COALESCE(PTC.TagCount, 0) AS TagCount,
    COALESCE(PC.CommentCount, 0) AS CommentCount,
    COALESCE(PV.UpVotes, 0) AS UpVotes,
    COALESCE(PV.DownVotes, 0) AS DownVotes,
    COALESCE(PHS.TotalEdits, 0) AS TotalEdits,
    PHS.LastEditDate,
    TU.Id AS TopUserId,
    TU.DisplayName AS TopUserName,
    TU.Reputation,
    TU.TotalBadges,
    TU.GoldBadges,
    TU.SilverBadges,
    TU.BronzeBadges,
    TU.UserRank
FROM 
    RankedPosts RP
LEFT JOIN 
    PostTagCounts PTC ON RP.Id = PTC.Id
LEFT JOIN 
    PostComments PC ON RP.Id = PC.PostId
LEFT JOIN 
    PostVotes PV ON RP.Id = PV.PostId
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
LEFT JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.Id
WHERE 
    RP.PostRank <= 10
ORDER BY 
    RP.PostRank, RP.Score DESC, RP.CreationDate;
