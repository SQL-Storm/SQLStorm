-- {"query": "12021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 796} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS UserPostRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0
),
TopUsers AS (
    SELECT 
        OwnerUserId,
        COUNT(Id) AS TotalPosts,
        SUM(Score) AS TotalScore,
        MAX(ViewCount) AS MaxViewCount
    FROM 
        RankedPosts
    WHERE 
        UserPostRank <= 3
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(Id) > 1
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostCount,
        AVG(P.Score) AS AvgScore,
        MAX(P.ViewCount) AS MaxViewCount
    FROM 
        Tags T
    JOIN 
        Posts P ON T.WikiPostId = P.Id OR T.ExcerptPostId = P.Id
    GROUP BY 
        T.TagName
),
PostHistorySummary AS (
    SELECT 
        PostId,
        COUNT(Id) AS TotalEdits,
        MAX(CASE WHEN PostHistoryTypeId = 5 THEN CreationDate END) AS LastEditBody,
        MAX(CASE WHEN PostHistoryTypeId = 6 THEN CreationDate END) AS LastEditTags
    FROM 
        PostHistory
    WHERE 
        PostHistoryTypeId IN (5, 6)
    GROUP BY 
        PostId
),
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(P.Id) FILTER (WHERE P.PostTypeId = 1) AS QuestionsAsked,
        COUNT(P.Id) FILTER (WHERE P.PostTypeId = 2) AS AnswersGiven,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Votes V ON U.Id = V.UserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
)
SELECT 
    TU.OwnerUserId,
    TU.TotalPosts,
    TU.TotalScore,
    TU.MaxViewCount,
    UA.DisplayName,
    UA.Reputation,
    UA.UserCreationDate,
    UA.QuestionsAsked,
    UA.AnswersGiven,
    UA.UpvotesReceived,
    UA.DownvotesReceived,
    TS.TagName,
    TS.PostCount,
    TS.AvgScore,
    TS.MaxViewCount,
    PHS.TotalEdits,
    PHS.LastEditBody,
    PHS.LastEditTags
FROM 
    TopUsers TU
JOIN 
    UserActivity UA ON TU.OwnerUserId = UA.Id
LEFT JOIN 
    TagStats TS ON TU.OwnerUserId = UA.Id
LEFT JOIN 
    PostHistorySummary PHS ON TU.OwnerUserId = UA.Id
ORDER BY 
    TU.TotalScore DESC, UA.Reputation DESC;
