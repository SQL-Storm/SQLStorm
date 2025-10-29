-- {"query": "1799.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2134} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS ProfileViews,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersCreated,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId IN (2, 3)) AS TotalPostVotesCast, -- UpMod/DownMod
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        MAX(P.CreationDate) AS LastPostDate,
        MIN(P.CreationDate) AS FirstPostDate
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Votes AS V ON U.Id = V.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes
),
PostEngagementMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        COALESCE(P.FavoriteCount, 0) AS FavoriteCount,
        (SELECT COUNT(DISTINCT V.Id) FROM Votes AS V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpvoteCount,
        (SELECT COUNT(DISTINCT V.Id) FROM Votes AS V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS DownvoteCount,
        (SELECT MAX(PH.CreationDate) FROM PostHistory AS PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (10, 11)) AS LastCloseReopenDate,
        (P.Score * 0.5 + COALESCE(P.ViewCount, 0) * 0.01 + COALESCE(P.AnswerCount, 0) * 2 + COALESCE(P.CommentCount, 0) * 0.2 + COALESCE(P.FavoriteCount, 0) * 3) AS EngagementScore,
        CASE
            WHEN P.PostTypeId = 1 AND COALESCE(P.ViewCount, 0) > 0
            THEN CAST(COALESCE(P.AnswerCount, 0) AS NUMERIC) / P.ViewCount
            ELSE NULL
        END AS AnswerToViewRatio,
        P.Tags,
        P.Title,
        P.Body
    FROM Posts AS P
    WHERE P.PostTypeId IN (1, 2)
),
TagPerformance AS (
    SELECT
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName,
        COUNT(DISTINCT P.Id) AS TotalTagPosts,
        SUM(P.Score) AS TotalTagScore,
        AVG(P.Score) AS AvgTagScore,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TagQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TagAnswers,
        MAX(P.CreationDate) AS LastTagActivity
    FROM Posts AS P
    WHERE P.Tags IS NOT NULL AND P.Tags != '' AND P.PostTypeId IN (1, 2)
    GROUP BY TagName
),
PostHistoryAnalysis AS (
    SELECT
        PH.PostId,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.Id END) AS EditCount,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) AS LastEditDate,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Id END) AS CloseCount,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.Id END) AS ReopenCount,
        MIN(PH.CreationDate) AS InitialActivityDate,
        MAX(PH.CreationDate) AS LatestHistoryDate,
        EXTRACT(EPOCH FROM (MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) - MIN(PH.CreationDate))) / 3600 AS TimeToFirstEditHours
    FROM PostHistory AS PH
    WHERE PH.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11)
    GROUP BY PH.PostId
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.ProfileViews,
    UAS.TotalPostsCreated,
    UAS.QuestionsCreated,
    UAS.AnswersCreated,
    UAS.TotalCommentsMade,
    UAS.TotalBadges,
    UAS.GoldBadges,
    SUM(PEM.PostScore) AS TotalPostScore,
    AVG(PEM.EngagementScore) AS AvgEngagementScore,
    MAX(PEM.ViewCount) AS MaxPostViews,
    COUNT(DISTINCT CASE WHEN PEM.PostTypeId = 1 AND PEM.AnswerToViewRatio IS NOT NULL AND PEM.AnswerToViewRatio < 0.01 THEN PEM.PostId END) AS LowAnswerRatioQuestions,
    AVG(PHA.EditCount) AS AvgPostEditCount,
    (
        SELECT TP_Inner.TagName
        FROM TagPerformance AS TP_Inner
        WHERE TP_Inner.TagName IN (
            SELECT TRIM(UNNEST(string_to_array(SUBSTRING(P_Inner.Tags, 2, LENGTH(P_Inner.Tags) - 2), '><')))
            FROM Posts AS P_Inner
            WHERE P_Inner.OwnerUserId = UAS.UserId AND P_Inner.Tags IS NOT NULL
        )
        ORDER BY TP_Inner.AvgTagScore DESC, TP_Inner.TotalTagPosts DESC
        LIMIT 1
    ) AS TopPerformingTagByUser,
    RANK() OVER (ORDER BY UAS.Reputation DESC, AVG(PEM.EngagementScore) DESC) AS UserReputationEngagementRank,
    AVG(CASE WHEN PEM.PostTypeId = 2 THEN PEM.PostScore ELSE NULL END) OVER (PARTITION BY UAS.UserId) AS UserAvgAnswerScore,
    EXTRACT(DAY FROM (UAS.LastPostDate - UAS.FirstPostDate)) AS DaysBetweenFirstAndLastPost,
    SUM(CASE WHEN PEM.PostTypeId = 1 AND PEM.PostScore < 0 THEN 1 ELSE 0 END) AS NegativeScoreQuestions,
    SUM(CASE WHEN PEM.PostTypeId = 2 AND PEM.PostScore < 0 THEN 1 ELSE 0 END) AS NegativeScoreAnswers,
    COALESCE(
        MAX(CASE WHEN LENGTH(PEM.Title) > 100 AND PEM.PostTypeId = 1 THEN SUBSTRING(PEM.Title, 1, 50) || '...' ELSE NULL END),
        'No Long Title Example'
    ) AS ExampleLongQuestionTitleSnippet,
    COUNT(DISTINCT CASE WHEN PHA.CloseCount > 0 AND PHA.ReopenCount > 0 THEN PEM.PostId END) AS ClosedAndReopenedPosts
FROM UserActivitySummary AS UAS
LEFT JOIN PostEngagementMetrics AS PEM ON UAS.UserId = PEM.OwnerUserId
LEFT JOIN PostHistoryAnalysis AS PHA ON PEM.PostId = PHA.PostId
WHERE
    UAS.Reputation > 1000 AND UAS.TotalPostsCreated > 5
    AND UAS.TotalBadges >= 3
    AND (
        PEM.PostTypeId IS NULL OR
        (
            PEM.PostScore > 5 OR PEM.FavoriteCount > 0
            OR EXISTS (SELECT 1 FROM Comments AS C WHERE C.PostId = PEM.PostId AND LENGTH(C.Text) > 100)
        )
    )
GROUP BY
    UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.ProfileViews, UAS.TotalPostsCreated,
    UAS.QuestionsCreated, UAS.AnswersCreated, UAS.TotalCommentsMade, UAS.TotalBadges,
    UAS.GoldBadges, UAS.LastPostDate, UAS.FirstPostDate
HAVING
    COUNT(PEM.PostId) > 0
    AND (SUM(COALESCE(PEM.UpvoteCount, 0)) - SUM(COALESCE(PEM.DownvoteCount, 0))) > 10
ORDER BY
    UserReputationEngagementRank ASC, UAS.UserId ASC
LIMIT 100;
