WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS ProfileViews,
        U.UpVotes AS TotalUpvotesGiven,
        U.DownVotes AS TotalDownvotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsAuthored,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsAuthored,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersAuthored,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(COALESCE(P.LastActivityDate, P.CreationDate, C.CreationDate, U.LastAccessDate)) AS LatestOverallUserActivityDate,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score END) AS AvgQuestionScoreAuthored,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score END) AS AvgAnswerScoreAuthored,
        NULLIF(SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score END), 0) AS TotalAnswerScore
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostHistoryDetails AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        COUNT(DISTINCT PH.RevisionGUID) AS UniqueRevisionCount,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) AS LatestEditDate,
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) AS EarliestEditDate,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TimesClosed,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TimesReopened,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (35, 36) THEN 1 ELSE 0 END) AS TimesMigrated,
        (
            SELECT CRT.Name
            FROM PostHistory PH_INNER
            LEFT JOIN CloseReasonTypes CRT ON CAST(PH_INNER.Comment AS SMALLINT) = CRT.Id
            WHERE PH_INNER.PostId = PH.PostId
              AND PH_INNER.PostHistoryTypeId = 10
            ORDER BY PH_INNER.CreationDate DESC
            LIMIT 1
        ) AS LastCloseReasonName,
        MAX(CASE WHEN PH.PostHistoryTypeId = 1 THEN PH.Text END) AS InitialTitleText,
        MAX(CASE WHEN PH.PostHistoryTypeId = 2 THEN LENGTH(PH.Text) END) AS InitialBodyContentLength
    FROM PostHistory PH
    GROUP BY PH.PostId
),
PostVoteAggregates AS (
    SELECT
        V.PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotesCount,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteMarksReceived
    FROM Votes V
    GROUP BY V.PostId
),
CommentMetrics AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalCommentsOnPost,
        AVG(C.Score) AS AvgCommentScore,
        SUM(CASE WHEN LOWER(C.Text) LIKE '%error%' OR LOWER(C.Text) LIKE '%bug%' OR LOWER(C.Text) LIKE '%issue%' THEN 1 ELSE 0 END) AS ProblemReportComments,
        SUM(CASE WHEN LOWER(C.Text) LIKE '%thanks%' OR LOWER(C.Text) LIKE '%great%' OR LOWER(C.Text) LIKE '%helpful%' THEN 1 ELSE 0 END) AS PositiveFeedbackComments
    FROM Comments C
    GROUP BY C.PostId
),
TagUsageAndPerformance AS (
    SELECT
        Q.Id AS QuestionId,
        TRIM(BOTH '<>' FROM UNNEST(string_to_array(SUBSTRING(Q.Tags FROM 2 FOR LENGTH(Q.Tags)-2), '><'))) AS TagName,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.AnswerCount AS QuestionAnswerCount,
        Q.CreationDate AS QuestionCreationDate
    FROM Posts Q
    WHERE Q.PostTypeId = 1 AND Q.Tags IS NOT NULL AND LENGTH(Q.Tags) > 2
),
AggregatedTagStats AS (
    SELECT
        T.TagName,
        COUNT(DISTINCT TUP.QuestionId) AS TotalQuestionsWithTag,
        AVG(TUP.QuestionScore) AS AvgScoreForTagQuestions,
        MAX(TUP.QuestionViewCount) AS MaxViewCountForTag,
        AVG(TUP.QuestionAnswerCount) AS AvgAnswerCountForTagQuestions,
        MIN(TUP.QuestionCreationDate) AS FirstTagUseDate
    FROM Tags T
    JOIN TagUsageAndPerformance TUP ON T.TagName = TUP.TagName
    LEFT JOIN Posts P ON TUP.QuestionId = P.Id
    GROUP BY T.TagName
)
SELECT
    UES.UserId,
    UES.DisplayName,
    UES.Reputation,
    UES.TotalPostsAuthored,
    UES.TotalQuestionsAuthored,
    UES.TotalAnswersAuthored,
    UES.TotalCommentsMade,
    UES.GoldBadges,
    UES.SilverBadges,
    UES.BronzeBadges,
    UES.LatestOverallUserActivityDate,
    UES.AvgQuestionScoreAuthored,
    UES.AvgAnswerScoreAuthored,
    Q.Id AS QuestionId,
    Q.Title AS QuestionTitle,
    Q.CreationDate AS QuestionCreationDate,
    Q.Score AS QuestionScore,
    Q.ViewCount AS QuestionViewCount,
    Q.AnswerCount AS QuestionAnswerCount,
    Q.FavoriteCount AS QuestionFavoriteCount,
    Q.LastActivityDate AS QuestionLastActivityDate,
    COALESCE(Q.ClosedDate, CAST('9999-12-31' AS TIMESTAMP)) AS QuestionClosedOrFutureDate,
    CASE
        WHEN Q.CommunityOwnedDate IS NOT NULL THEN 'CommunityWiki'
        WHEN Q.OwnerUserId IS NULL THEN 'OwnerDeleted'
        ELSE 'UserOwned'
    END AS QuestionOwnershipType,
    PHD_Q.UniqueRevisionCount AS QuestionEditCount,
    PHD_Q.LatestEditDate AS QuestionLastEditDate,
    PHD_Q.InitialTitleText AS QuestionInitialTitle,
    PHD_Q.InitialBodyContentLength AS QuestionInitialBodyLength,
    PHD_Q.TimesClosed AS QuestionClosureCount,
    PHD_Q.LastCloseReasonName AS QuestionLastClosureReason,
    PHD_Q.TimesReopened AS QuestionReopenCount,
    PVA_Q.UpVotesReceived AS QuestionUpvotesReceived,
    PVA_Q.DownVotesReceived AS QuestionDownvotesReceived,
    CM_Q.TotalCommentsOnPost AS QuestionTotalComments,
    CM_Q.AvgCommentScore AS QuestionAvgCommentScore,
    CM_Q.ProblemReportComments AS QuestionProblemComments,
    AcceptedAnswer.Id AS AcceptedAnswerId,
    AcceptedAnswer.Score AS AcceptedAnswerScore,
    AcceptedAnswer.CreationDate AS AcceptedAnswerCreationDate,
    AcceptedAnswer.LastActivityDate AS AcceptedAnswerLastActivityDate,
    PHD_A.UniqueRevisionCount AS AcceptedAnswerEditCount,
    PVA_A.UpVotesReceived AS AcceptedAnswerUpvotesReceived,
    PVA_A.DownVotesReceived AS AcceptedAnswerDownvotesReceived,
    CM_A.TotalCommentsOnPost AS AcceptedAnswerTotalComments,
    Q_FirstTag.FirstTag AS MainQuestionTag,
    ATS.TotalQuestionsWithTag AS MainTagTotalQuestions,
    ATS.AvgScoreForTagQuestions AS MainTagAvgQuestionScore,
    (
        SELECT COUNT(PL.Id)
        FROM PostLinks PL
        WHERE PL.PostId = Q.Id AND PL.LinkTypeId = 3
    ) AS DuplicateLinksFromQuestion,
    (
        SELECT COUNT(PL.Id)
        FROM PostLinks PL
        WHERE PL.RelatedPostId = Q.Id AND PL.LinkTypeId = 3
    ) AS DuplicatedByLinksToQuestion,
    CAST(Q.Score AS DECIMAL) / NULLIF(Q.ViewCount, 0) AS QuestionEngagementRatio,
    RANK() OVER (PARTITION BY DATE_TRUNC('quarter', Q.CreationDate) ORDER BY Q.Score DESC, Q.ViewCount DESC) AS RankByScoreAndViewsInQuarter,
    AVG(Q.AnswerCount) OVER (PARTITION BY EXTRACT(YEAR FROM Q.CreationDate)) AS AvgAnswerCountForYear,
    LAG(Q.Score, 1, 0) OVER (PARTITION BY UES.UserId ORDER BY Q.CreationDate) AS PreviousQuestionScoreByOwner,
    UES.TotalAnswerScore / NULLIF(UES.TotalAnswersAuthored, 0) AS UserAvgAnswerScoreOverall,
    CASE
        WHEN UES.Reputation > 50000 AND UES.GoldBadges >= 5 AND UES.TotalQuestionsAuthored > 100 AND UES.AvgQuestionScoreAuthored > 20
            THEN 'Elite Contributor'
        WHEN UES.Reputation BETWEEN 10000 AND 50000 AND UES.TotalPostsAuthored > 200 AND UES.TotalCommentsMade > 50
            THEN 'High-Activity Veteran'
        WHEN UES.UserCreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year') AND UES.TotalPostsAuthored < 10
            THEN 'Newbie - Low Activity'
        WHEN Q.Title ILIKE '%javascript%' OR Q.Tags ILIKE '%<javascript>%' THEN 'JavaScript Related'
        ELSE 'General User/Post'
    END AS UserPostClassification,
    (
        SELECT MAX(P_PRIOR.CreationDate)
        FROM Posts P_PRIOR
        WHERE P_PRIOR.OwnerUserId = UES.UserId
          AND P_PRIOR.CreationDate < Q.CreationDate
          AND P_PRIOR.Score >= 10
          AND P_PRIOR.PostTypeId = 1
    ) AS LastHighScoringQuestionDateByOwner
FROM UserEngagementSummary UES
LEFT JOIN Posts Q ON UES.UserId = Q.OwnerUserId AND Q.PostTypeId = 1
LEFT JOIN PostHistoryDetails PHD_Q ON Q.Id = PHD_Q.PostId
LEFT JOIN PostVoteAggregates PVA_Q ON Q.Id = PVA_Q.PostId
LEFT JOIN CommentMetrics CM_Q ON Q.Id = CM_Q.PostId
LEFT JOIN Posts AcceptedAnswer ON Q.AcceptedAnswerId = AcceptedAnswer.Id AND AcceptedAnswer.PostTypeId = 2
LEFT JOIN PostHistoryDetails PHD_A ON AcceptedAnswer.Id = PHD_A.PostId
LEFT JOIN PostVoteAggregates PVA_A ON AcceptedAnswer.Id = PVA_A.PostId
LEFT JOIN CommentMetrics CM_A ON AcceptedAnswer.Id = CM_A.PostId
LEFT JOIN (
    SELECT
        P_TAG.Id AS QuestionId,
        TRIM(BOTH '<>' FROM SPLIT_PART(SUBSTRING(P_TAG.Tags FROM 2 FOR LENGTH(P_TAG.Tags)-2), '><', 1)) AS FirstTag
    FROM Posts P_TAG
    WHERE P_TAG.PostTypeId = 1 AND P_TAG.Tags IS NOT NULL AND LENGTH(P_TAG.Tags) > 2
) Q_FirstTag ON Q.Id = Q_FirstTag.QuestionId
LEFT JOIN AggregatedTagStats ATS ON Q_FirstTag.FirstTag = ATS.TagName
WHERE
    UES.Reputation > 500
    AND Q.CreationDate IS NOT NULL AND Q.CreationDate BETWEEN CAST('2022-01-01' AS DATE) AND CAST('2023-12-31' AS DATE)
    AND Q.ViewCount > 1000
    AND (Q.Tags ILIKE '%<sql>%' OR Q.Tags ILIKE '%<database>%' OR Q.Tags ILIKE '%<performance>%' OR Q.Tags ILIKE '%<query>%')
    AND (COALESCE(PHD_Q.TimesClosed, 0) = 0 OR COALESCE(PHD_Q.TimesReopened, 0) > 0)
    AND UES.LatestOverallUserActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 months')
    AND AcceptedAnswer.Id IS NOT NULL
    AND Q.Body ILIKE '%<pre><code>%'
ORDER BY UES.Reputation DESC, QuestionScore DESC, QuestionCreationDate DESC, QuestionViewCount DESC
LIMIT 5000;