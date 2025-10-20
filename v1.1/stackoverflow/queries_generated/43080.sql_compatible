WITH TopUsers AS (
    SELECT U.Id, U.DisplayName, U.Reputation, COUNT(DISTINCT P.Id) AS PostsCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE P.CreationDate BETWEEN CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 YEAR' AND CAST('2024-10-01 12:34:56' AS timestamp)
    GROUP BY U.Id, U.DisplayName, U.Reputation
    ORDER BY U.Reputation DESC, PostsCount DESC
    LIMIT 100
),
UserActivity AS (
    SELECT 
        TU.Id AS UserId,
        COUNT(DISTINCT PH.PostId) AS EditedPosts,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) THEN 1 ELSE 0 END) AS ContentEdits,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 11, 12, 13) THEN 1 ELSE 0 END) AS ModerationActions,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived
    FROM TopUsers TU
    LEFT JOIN PostHistory PH ON TU.Id = PH.UserId
    LEFT JOIN Votes V ON TU.Id = V.UserId
    WHERE PH.CreationDate BETWEEN CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 YEAR' AND CAST('2024-10-01 12:34:56' AS timestamp)
    GROUP BY TU.Id
),
AnswerStatistics AS (
    SELECT 
        P.OwnerUserId,
        COUNT(DISTINCT P.Id) AS AnswerCount,
        AVG(P.Score) AS AvgAnswerScore,
        SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswers
    FROM Posts P
    WHERE P.PostTypeId = 2
        AND P.CreationDate BETWEEN CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 YEAR' AND CAST('2024-10-01 12:34:56' AS timestamp)
    GROUP BY P.OwnerUserId
)
SELECT 
    TU.DisplayName,
    TU.Reputation,
    UA.EditedPosts,
    UA.ContentEdits,
    UA.ModerationActions,
    UA.UpvotesReceived,
    UA.DownvotesReceived,
    COALESCE(ASstats.AnswerCount, 0) AS AnswerCount,
    COALESCE(ASstats.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(ASstats.AcceptedAnswers, 0) AS AcceptedAnswers
FROM TopUsers TU
LEFT JOIN UserActivity UA ON TU.Id = UA.UserId
LEFT JOIN AnswerStatistics ASstats ON TU.Id = ASstats.OwnerUserId
ORDER BY TU.Reputation DESC, UA.EditedPosts DESC, AnswerCount DESC;