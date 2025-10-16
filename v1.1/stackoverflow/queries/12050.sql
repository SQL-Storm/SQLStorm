WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName AS OwnerDisplayName,
        P.OwnerUserId,
        P.Tags,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 2) OVER (PARTITION BY P.Id) AS UpVotes,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 3) OVER (PARTITION BY P.Id) AS DownVotes
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.PostTypeId IN (1, 2)
),
TopUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        COUNT(CASE WHEN P.PostTypeId = 1 THEN 1 END) AS QuestionsAsked,
        COUNT(CASE WHEN P.PostTypeId = 2 THEN 1 END) AS AnswersGiven,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore,
        AVG(P.Score) AS AvgScore
    FROM 
        Tags T
    INNER JOIN 
        Posts P ON POSITION(T.TagName IN REPLACE(REPLACE(P.Tags, '><', ','), '<', '')) > 0
        -- The Posts.Tags value is assumed to be like '<tag1><tag2>'; convert to comma-separated for POSITION search
    WHERE 
        P.PostTypeId = 1
    GROUP BY 
        T.TagName
),
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(PH.Id) AS RevisionCount,
        MAX(PH.CreationDate) AS LastRevisionDate
    FROM 
        PostHistory PH
    WHERE 
        PH.PostHistoryTypeId IN (2, 5, 6)
    GROUP BY 
        PH.PostId
),
CommunityPosts AS (
    SELECT 
        P.Id,
        P.Title,
        COUNT(PH.Id) AS CommunityBumpCount
    FROM 
        Posts P
    LEFT JOIN 
        PostHistory PH ON P.Id = PH.PostId AND PH.PostHistoryTypeId = 50
    WHERE 
        P.CommunityOwnedDate IS NOT NULL
    GROUP BY 
        P.Id, P.Title
)
SELECT 
    RP.Id,
    RP.PostTypeId,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerDisplayName,
    RP.PostRank,
    RP.UpVotes,
    RP.DownVotes,
    TU.DisplayName AS TopUser,
    TU.Reputation,
    TU.QuestionsAsked,
    TU.AnswersGiven,
    TU.UserRank,
    TS.TagName,
    TS.PostCount,
    TS.TotalScore,
    TS.AvgScore,
    PHS.RevisionCount,
    PHS.LastRevisionDate,
    CP.Title AS CommunityTitle,
    CP.CommunityBumpCount
FROM 
    RankedPosts RP
LEFT JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.Id AND TU.UserRank <= 10
LEFT JOIN 
    TagStats TS ON POSITION(TS.TagName IN REPLACE(REPLACE(RP.Tags, '><', ','), '<', '')) > 0
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
LEFT JOIN 
    CommunityPosts CP ON RP.Id = CP.Id
WHERE 
    RP.PostRank <= 50
ORDER BY 
    RP.Score DESC, RP.CreationDate;