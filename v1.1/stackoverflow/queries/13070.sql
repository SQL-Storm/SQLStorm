WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsPosted,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersPosted,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) DESC) AS QuestionRank
    FROM
        Users U
        LEFT JOIN Posts P ON U.Id = P.OwnerUserId
        LEFT JOIN Votes V ON P.Id = V.PostId
    WHERE
        U.Reputation > 1000
        AND P.CreationDate > (DATE '2024-10-01' - INTERVAL '1' YEAR)
    GROUP BY
        U.Id, U.DisplayName, U.Reputation
),
PostMetrics AS (
    SELECT
        P.Id AS PostId,
        P.Title,
        P.ViewCount,
        P.Score,
        (EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - P.CreationDate)) / 86400) AS DaysSinceCreation,
        COALESCE(SUM(CASE WHEN PH.PostHistoryTypeId = 5 THEN 1 ELSE 0 END), 0) AS EditCount,
        LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousScore,
        P.OwnerUserId
    FROM
        Posts P
        LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE
        P.PostTypeId = 1
    GROUP BY
        P.Id, P.Title, P.ViewCount, P.Score, P.CreationDate, P.OwnerUserId
)
SELECT
    UA.UserId,
    UA.DisplayName,
    UA.Reputation,
    UA.QuestionsPosted,
    UA.AnswersPosted,
    UA.UpVotesReceived,
    UA.DownVotesReceived,
    PM.PostId,
    PM.Title,
    PM.ViewCount,
    PM.Score,
    PM.DaysSinceCreation,
    PM.EditCount,
    (PM.Score - PM.PreviousScore) AS ScoreChange,
    DENSE_RANK() OVER (PARTITION BY UA.UserId ORDER BY PM.ViewCount DESC) AS UserPostRank
FROM
    UserActivity UA
    JOIN PostMetrics PM ON UA.UserId = PM.OwnerUserId
WHERE
    UA.QuestionRank <= 100
    AND PM.DaysSinceCreation < 365
    AND (PM.Score > 5 OR PM.ViewCount > 1000)
ORDER BY
    UA.QuestionsPosted DESC, PM.ViewCount DESC;