-- {"query": "12068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 884} 

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
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2)
),
TopPosts AS (
    SELECT 
        Id, 
        PostTypeId, 
        Score,
        ViewCount,
        CreationDate,
        OwnerUserId,
        OwnerDisplayName
    FROM 
        RankedPosts
    WHERE 
        UserPostRank <= 3
),
AggregatedData AS (
    SELECT 
        T.TagName,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        AVG(P.Score) AS AvgScore,
        SUM(P.ViewCount) AS TotalViews,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        MAX(P.CreationDate) AS LatestPostDate
    FROM 
        Tags T
    JOIN 
        Posts P ON T.Id = ANY(string_to_array(P.Tags, '<', '>'))
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        T.TagName
),
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsPosted,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersPosted,
        COUNT(DISTINCT C.Id) AS CommentsMade,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Comments C ON U.Id = C.UserId
    LEFT JOIN 
        Votes V ON U.Id = V.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
TagPerformance AS (
    SELECT 
        A.TagName,
        A.TotalPosts,
        A.AvgScore,
        A.TotalViews,
        A.TotalQuestions,
        A.TotalAnswers,
        A.LatestPostDate,
        ROW_NUMBER() OVER (ORDER BY A.TotalPosts DESC) AS PostRank,
        ROW_NUMBER() OVER (ORDER BY A.AvgScore DESC) AS ScoreRank,
        ROW_NUMBER() OVER (ORDER BY A.TotalViews DESC) AS ViewRank
    FROM 
        AggregatedData A
)
SELECT 
    U.DisplayName,
    U.QuestionsPosted,
    U.AnswersPosted,
    U.CommentsMade,
    U.UpVotesGiven,
    U.DownVotesGiven,
    TP.TagName AS TopTag,
    TP.TotalPosts AS TopTagTotalPosts,
    TP.AvgScore AS TopTagAvgScore,
    TP.TotalViews AS TopTagTotalViews
FROM 
    UserActivity U
LEFT JOIN 
    LATERAL (
        SELECT 
            TP.TagName,
            TP.TotalPosts,
            TP.AvgScore,
            TP.TotalViews
        FROM 
            TagPerformance TP
        WHERE 
            TP.TagName = ANY(string_to_array(U.DisplayName, ' '))
        ORDER BY 
            TP.TotalPosts DESC
        LIMIT 1
    ) TP ON true
WHERE 
    U.QuestionsPosted > 0 OR U.AnswersPosted > 0
ORDER BY 
    U.QuestionsPosted DESC, 
    U.AnswersPosted DESC;
