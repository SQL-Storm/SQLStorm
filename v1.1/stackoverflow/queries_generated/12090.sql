-- {"query": "12090.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 892} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
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
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        COUNT(B.Id) FILTER (WHERE B.Class = 1) AS GoldBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 2) AS SilverBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 3) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, U.CreationDate) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore,
        AVG(P.Score) AS AvgScore,
        MAX(P.CreationDate) AS LatestPostDate
    FROM 
        Tags T
    JOIN 
        Posts P ON T.Id = ANY(string_to_array(P.Tags, '<', '>'))
    GROUP BY 
        T.TagName
),
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(PH.Id) AS TotalEdits,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditBodyDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 6 THEN PH.CreationDate END) AS LastEditTagsDate
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
    RP.UpVotes,
    RP.DownVotes,
    RP.CommentCount,
    TU.Id AS TopUserId,
    TU.DisplayName AS TopUserName,
    TU.Reputation,
    TU.GoldBadges,
    TU.SilverBadges,
    TU.BronzeBadges,
    TU.UserRank,
    TS.TagName,
    TS.PostCount,
    TS.TotalScore,
    TS.AvgScore,
    TS.LatestPostDate,
    PHS.TotalEdits,
    PHS.LastEditBodyDate,
    PHS.LastEditTagsDate
FROM 
    RankedPosts RP
JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.Id
JOIN 
    TagStats TS ON TS.TagName = ANY(string_to_array(RP.Tags, '<', '>'))
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
WHERE 
    RP.PostRank <= 10
    AND TU.UserRank <= 10
ORDER BY 
    RP.PostRank, 
    TU.UserRank;
