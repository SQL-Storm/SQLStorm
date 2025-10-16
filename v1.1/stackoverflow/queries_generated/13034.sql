-- {"query": "13034.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 725} 

WITH UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsAsked,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersProvided,
        COUNT(DISTINCT PH.PostId) AS PostsEdited,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        ROW_NUMBER() OVER (ORDER BY (COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) + COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0)) DESC) AS Rank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN PostHistory PH ON U.Id = PH.UserId AND PH.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE U.Reputation > 1000
    GROUP BY U.Id, U.DisplayName
),
TopPerformers AS (
    SELECT *
    FROM UserActivity
    WHERE Rank <= 10
),
PostDetails AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        U.DisplayName AS OwnerDisplayName,
        COUNT(V.Id) AS TotalVotes
    FROM Posts P
    JOIN Users U ON P.OwnerUserId = U.Id
    LEFT JOIN Votes V ON P.Id = V.PostId
    WHERE P.PostTypeId = 1 AND P.ClosedDate IS NULL
    GROUP BY P.Id, P.Title, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, U.DisplayName
),
AggregatedPostMetrics AS (
    SELECT 
        TP.Id AS UserId,
        TP.DisplayName,
        AVG(PD.Score) AS AvgScore,
        SUM(PD.ViewCount) AS TotalViewCount,
        SUM(PD.AnswerCount) AS TotalAnswers,
        SUM(PD.CommentCount) AS TotalComments,
        SUM(PD.TotalVotes) AS TotalVotesReceived
    FROM TopPerformers TP
    JOIN PostDetails PD ON TP.Id = PD.OwnerDisplayName
    GROUP BY TP.Id, TP.DisplayName
)
SELECT 
    U.DisplayName,
    U.QuestionsAsked,
    U.AnswersProvided,
    U.PostsEdited,
    U.GoldBadges,
    A.AvgScore,
    A.TotalViewCount,
    A.TotalAnswers,
    A.TotalComments,
    A.TotalVotesReceived
FROM UserActivity U
JOIN AggregatedPostMetrics A ON U.Id = A.UserId
WHERE U.Rank <= 10
ORDER BY A.TotalVotesReceived DESC;
