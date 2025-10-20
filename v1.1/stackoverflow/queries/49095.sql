WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsWritten,
        SUM(CASE WHEN V.VoteTypeId = 2 AND VP.OwnerUserId = U.Id THEN 1 ELSE 0 END) AS TotalUpvotesReceivedOnPosts,
        SUM(CASE WHEN V.VoteTypeId = 3 AND VP.OwnerUserId = U.Id THEN 1 ELSE 0 END) AS TotalDownvotesReceivedOnPosts,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN Posts VP ON V.PostId = VP.Id
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
QuestionTagUsage AS (
    -- For portability, parse tags by removing leading/trailing <> and splitting on '><'
    SELECT
        P.OwnerUserId AS UserId,
        TRIM(tag) AS TagName
    FROM Posts P,
    LATERAL (
        SELECT REGEXP_SPLIT_TO_TABLE(
            SUBSTRING(P.Tags FROM 2 FOR (LENGTH(P.Tags) - 2)),
            '\>\<'
        ) AS tag
    ) s
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
UserTop3Tags AS (
    SELECT
        RankedTags.UserId,
        STRING_AGG(RankedTags.TagName, ', ' ORDER BY RankedTags.TagCount DESC, RankedTags.TagName ASC) AS Top3TagsList
    FROM (
        SELECT
            qtu.UserId,
            qtu.TagName,
            COUNT(*) AS TagCount,
            ROW_NUMBER() OVER(PARTITION BY qtu.UserId ORDER BY COUNT(*) DESC, qtu.TagName ASC) AS rn
        FROM QuestionTagUsage qtu
        GROUP BY qtu.UserId, qtu.TagName
    ) RankedTags
    WHERE RankedTags.rn <= 3
    GROUP BY RankedTags.UserId
),
PostHistoricalEvents AS (
    SELECT
        PH.PostId,
        SUM(CASE WHEN PH.PostHistoryTypeId = 16 THEN 1 ELSE 0 END) AS CommunityOwnedEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (35, 36) THEN 1 ELSE 0 END) AS MigrationEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosedEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenedEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId = 19 THEN 1 ELSE 0 END) AS ProtectedEvents
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (10, 11, 16, 19, 35, 36)
    GROUP BY PH.PostId
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalQuestionsOwned,
    UAS.TotalAnswersOwned,
    UAS.TotalCommentsWritten,
    UAS.TotalUpvotesReceivedOnPosts,
    UAS.TotalDownvotesReceivedOnPosts,
    UAS.TotalBadgesEarned,
    UTT.Top3TagsList,
    SUM(P.Score) AS TotalQuestionScore,
    AVG(P.Score) AS AverageQuestionScore,
    SUM(P.ViewCount) AS TotalQuestionViewCount,
    SUM(P.AnswerCount) AS TotalAnswersReceivedOnQuestions,
    SUM(P.FavoriteCount) AS TotalFavoriteCountOnQuestions,
    SUM(COALESCE(PHE.CommunityOwnedEvents, 0)) AS SumCommunityOwnedEventsOnQuestions,
    SUM(COALESCE(PHE.MigrationEvents, 0)) AS SumMigrationEventsOnQuestions,
    SUM(COALESCE(PHE.ClosedEvents, 0)) AS SumClosedEventsOnQuestions,
    SUM(COALESCE(PHE.ReopenedEvents, 0)) AS SumReopenedEventsOnQuestions,
    SUM(COALESCE(PHE.ProtectedEvents, 0)) AS SumProtectedEventsOnQuestions,
    MAX(P.LastActivityDate) AS LastQuestionActivity
FROM UserActivitySummary UAS
JOIN Posts P ON UAS.UserId = P.OwnerUserId
LEFT JOIN UserTop3Tags UTT ON UAS.UserId = UTT.UserId
LEFT JOIN PostHistoricalEvents PHE ON P.Id = PHE.PostId
WHERE P.PostTypeId = 1
  AND P.CreationDate >= DATE '2020-01-01'
  AND (
        P.Score > 10 OR
        P.AnswerCount > 5 OR
        P.ViewCount > 1000 OR
        P.FavoriteCount > 5 OR
        P.CommunityOwnedDate IS NOT NULL OR
        COALESCE(PHE.MigrationEvents, 0) > 0 OR
        COALESCE(PHE.ClosedEvents, 0) > 0
      )
GROUP BY
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalQuestionsOwned,
    UAS.TotalAnswersOwned,
    UAS.TotalCommentsWritten,
    UAS.TotalUpvotesReceivedOnPosts,
    UAS.TotalDownvotesReceivedOnPosts,
    UAS.TotalBadgesEarned,
    UTT.Top3TagsList
HAVING UAS.Reputation > 5000
   AND SUM(P.Score) > 50
   AND UAS.TotalQuestionsOwned > 10
ORDER BY UAS.Reputation DESC, TotalQuestionScore DESC, TotalQuestionsOwned DESC
LIMIT 200;