WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsOwned,
        COUNT(CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersOwned,
        SUM(COALESCE(P.Score, 0)) AS TotalScoreOnOwnedPosts,
        COUNT(C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN VR.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN VR.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        DATE_PART('year', AGE(U.LastAccessDate, U.CreationDate)) AS YearsOnPlatform
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes VR ON P.Id = VR.PostId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
        U.Views, U.UpVotes, U.DownVotes
),
QuestionBaseMetrics AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.Title AS QuestionTitle,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.CommentCount AS QuestionCommentCount,
        Q.FavoriteCount,
        Q.ClosedDate,
        Q.AcceptedAnswerId,
        Q.AnswerCount,
        CASE WHEN Q.Tags IS NOT NULL AND LENGTH(TRIM(Q.Tags)) > 2 THEN TRUE ELSE FALSE END AS HasTags,
        CASE WHEN Q.ClosedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsClosed,
        CASE WHEN Q.ViewCount > 1000 AND Q.FavoriteCount > 50 THEN 'Hot'
             WHEN Q.ViewCount > 100 AND Q.FavoriteCount > 5 THEN 'Warm'
             ELSE 'Cold' END AS QuestionTemperature
    FROM Posts Q
    WHERE Q.PostTypeId = 1
),
QuestionAnswerStats AS (
    SELECT
        QBM.QuestionId,
        MIN(EXTRACT(EPOCH FROM (A.CreationDate - QBM.QuestionCreationDate)))/3600.0 AS HoursToFirstAnswer,
        AVG(A.Score) AS AvgAnswerScore,
        MAX(CASE WHEN A.Score > 5 THEN 1 ELSE 0 END) AS HasHighlyVotedAnswer
    FROM QuestionBaseMetrics QBM
    LEFT JOIN Posts A ON QBM.QuestionId = A.ParentId AND A.PostTypeId = 2
    GROUP BY QBM.QuestionId
),
QuestionHistoryStats AS (
    SELECT
        QBM.QuestionId,
        COUNT(DISTINCT PH_Edit.UserId) FILTER (WHERE PH_Edit.PostHistoryTypeId IN (4, 5, 6)) AS NumberOfUniqueEditors,
        (
            SELECT CR.Name
            FROM PostHistory PH_Close
            JOIN CloseReasonTypes CR ON CAST(PH_Close.Comment AS INTEGER) = CR.Id
            WHERE PH_Close.PostId = QBM.QuestionId AND PH_Close.PostHistoryTypeId = 10
            ORDER BY PH_Close.CreationDate DESC
            LIMIT 1
        ) AS LatestCloseReason
    FROM QuestionBaseMetrics QBM
    LEFT JOIN PostHistory PH_Edit ON QBM.QuestionId = PH_Edit.PostId
    GROUP BY QBM.QuestionId
),
QuestionPerformance AS (
    SELECT
        QBM.QuestionId,
        QBM.QuestionOwnerId,
        QBM.QuestionTitle,
        QBM.QuestionCreationDate,
        QBM.QuestionScore,
        QBM.ViewCount,
        QBM.QuestionCommentCount AS CommentCount,
        QBM.FavoriteCount,
        QBM.ClosedDate,
        QBM.AcceptedAnswerId,
        QBM.AnswerCount,
        QBM.HasTags,
        QBM.IsClosed,
        QBM.QuestionTemperature,
        QAS.HoursToFirstAnswer,
        QAS.AvgAnswerScore,
        QAS.HasHighlyVotedAnswer,
        QHS.NumberOfUniqueEditors,
        QHS.LatestCloseReason
    FROM QuestionBaseMetrics QBM
    LEFT JOIN QuestionAnswerStats QAS ON QBM.QuestionId = QAS.QuestionId
    LEFT JOIN QuestionHistoryStats QHS ON QBM.QuestionId = QHS.QuestionId
),
TagMetrics AS (
    WITH RawTags AS (
        SELECT
            P.Id AS PostId,
            P.Score AS PostScore,
            P.OwnerUserId AS PostOwnerId,
            UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')) AS TagName
        FROM Posts P
        WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(TRIM(P.Tags)) > 2
    )
    SELECT
        RT.TagName,
        COUNT(DISTINCT RT.PostId) AS TotalTaggedQuestions,
        AVG(RT.PostScore) AS AvgScoreOfTaggedQuestions,
        COUNT(DISTINCT RT.PostOwnerId) AS UniqueTagContributors,
        RANK() OVER (ORDER BY AVG(RT.PostScore) DESC, COUNT(DISTINCT RT.PostId) DESC) AS TagScoreRank
    FROM RawTags RT
    GROUP BY RT.TagName
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        SUM(CASE WHEN B.TagBased THEN 1 ELSE 0 END) AS TagBasedBadges
    FROM Badges B
    GROUP BY B.UserId
),
TopQuestionUsers AS (
    SELECT DISTINCT QuestionOwnerId AS UserId
    FROM QuestionPerformance
    WHERE QuestionScore >= 50 OR FavoriteCount >= 10
),
HighlyEngagedUsers AS (
    SELECT UserId
    FROM UserActivitySummary
    WHERE TotalPostsOwned > 100
      AND TotalCommentsMade > 50
      AND TotalUpvotesReceived > 200
),
GoldBadgeUsers AS (
    SELECT UserId FROM UserBadgeSummary WHERE GoldBadges > 0
),
UsersWithAcceptedAnswers AS (
    SELECT DISTINCT QuestionOwnerId AS UserId
    FROM QuestionPerformance
    WHERE AcceptedAnswerId IS NOT NULL
),
GoldBadgeNoAcceptedAnswerUsers AS (
    SELECT UserId FROM GoldBadgeUsers
    EXCEPT
    SELECT UserId FROM UsersWithAcceptedAnswers
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.YearsOnPlatform,
    UAS.TotalPostsOwned,
    UAS.TotalQuestionsOwned,
    UAS.TotalAnswersOwned,
    UAS.TotalUpvotesReceived,
    UAS.TotalDownvotesReceived,
    COALESCE(UBS.TotalBadges, 0) AS TotalBadges,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(UBS.TagBasedBadges, 0) AS TagBasedBadges,
    COALESCE(AVG(QP.QuestionScore) FILTER (WHERE QP.QuestionOwnerId = UAS.UserId), 0.0) AS AvgOwnedQuestionScore,
    COUNT(CASE WHEN QP.QuestionTemperature = 'Hot' AND QP.QuestionOwnerId = UAS.UserId THEN 1 END) AS HotQuestionsOwnedCount,
    CAST(SUM(CASE WHEN QP.AcceptedAnswerId IS NOT NULL AND QP.QuestionOwnerId = UAS.UserId THEN 1 ELSE 0 END) AS DECIMAL) /
      NULLIF(SUM(CASE WHEN QP.QuestionOwnerId = UAS.UserId AND QP.AnswerCount > 0 THEN 1 ELSE 0 END), 0) AS AcceptanceRatioForOwnedQuestions,
    DENSE_RANK() OVER (PARTITION BY UAS.YearsOnPlatform ORDER BY UAS.Reputation DESC, UAS.LastAccessDate DESC) AS ReputationRankInCohort,
    SUM(UAS.TotalUpvotesReceived) OVER (ORDER BY UAS.UserCreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeUpvotesByCreationDate
FROM UserActivitySummary UAS
LEFT JOIN UserBadgeSummary UBS ON UAS.UserId = UBS.UserId
LEFT JOIN QuestionPerformance QP ON UAS.UserId = QP.QuestionOwnerId
GROUP BY
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.YearsOnPlatform,
    UAS.TotalPostsOwned,
    UAS.TotalQuestionsOwned,
    UAS.TotalAnswersOwned,
    UAS.TotalUpvotesReceived,
    UAS.TotalDownvotesReceived,
    UBS.TotalBadges,
    UBS.GoldBadges,
    UBS.SilverBadges,
    UBS.BronzeBadges,
    UBS.TagBasedBadges,
    UAS.LastAccessDate,
    UAS.UserCreationDate;