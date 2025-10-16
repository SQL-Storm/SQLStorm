-- {"query": "12046.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 830} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
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
        U.DisplayName,
        U.Reputation,
        COUNT(P.Id) FILTER (WHERE P.PostTypeId = 1) AS QuestionsAsked,
        COUNT(P.Id) FILTER (WHERE P.PostTypeId = 2) AS AnswersGiven,
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
    LEFT JOIN 
        Posts P ON T.Id = ANY(string_to_array(P.Tags, '><'))
    GROUP BY 
        T.TagName
),
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(PH.Id) AS RevisionCount,
        MAX(PH.CreationDate) AS LastRevisionDate,
        STRING_AGG(PHT.Name, ', ') WITHIN GROUP (ORDER BY PH.CreationDate DESC) AS RevisionTypes
    FROM 
        PostHistory PH
    JOIN 
        PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    GROUP BY 
        PH.PostId
)
SELECT 
    RP.Id,
    RP.PostTypeId,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    RP.Reputation,
    RP.PostRank,
    RP.UpVotes,
    RP.DownVotes,
    RP.CommentCount,
    COALESCE(TU.QuestionsAsked, 0) AS QuestionsAsked,
    COALESCE(TU.AnswersGiven, 0) AS AnswersGiven,
    TS.TagName,
    TS.PostCount,
    TS.TotalScore,
    TS.AvgScore,
    PHS.RevisionCount,
    PHS.LastRevisionDate,
    PHS.RevisionTypes
FROM 
    RankedPosts RP
LEFT JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.Id
LEFT JOIN 
    TagStats TS ON RP.Tags LIKE '%' || TS.TagName || '%'
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
WHERE 
    RP.PostRank <= 10
    AND TU.UserRank <= 10
ORDER BY 
    RP.Score DESC, 
    RP.CreationDate;
