WITH PopularTags AS (
    SELECT TagName
    FROM Tags
    WHERE Count > (SELECT AVG(Count) * 5 FROM Tags)
),
UserBadgeCounts AS (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(Id) AS TotalBadges
    FROM Badges
    GROUP BY UserId
),
HighlyEngagingQuestions AS (
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId,
        P.CreationDate AS QuestionCreationDate,
        P.Score AS QuestionScore,
        P.ViewCount,
        P.AnswerCount,
        P.Tags,
        COUNT(DISTINCT C.Id) AS QuestionCommentCount,
        SUM(CASE WHEN A.Id IS NOT NULL THEN A.Score ELSE 0 END) AS TotalAnswerScore
    FROM Posts AS P
    LEFT JOIN Comments AS C ON P.Id = C.PostId
    LEFT JOIN Posts AS A ON P.Id = A.ParentId AND A.PostTypeId = 2
    WHERE P.PostTypeId = 1
      AND P.ViewCount > 50000
      AND P.Score > 100
      AND P.CreationDate >= DATE '2021-01-01'
      AND EXISTS (
          SELECT 1
          FROM PopularTags AS PT
          WHERE PT.TagName = ANY (
            -- convert P.Tags like '<tag1><tag2>' into an array of tag names
            regexp_split_to_array(trim(BOTH '<>' FROM P.Tags), '><')
          )
      )
    GROUP BY P.Id, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.Tags
),
UserQuestionContributions AS (
    SELECT
        HEQ.OwnerUserId AS UserId,
        COUNT(HEQ.QuestionId) AS NumberOfHighlyEngagingQuestions,
        SUM(HEQ.QuestionScore) AS SumOfQuestionScores,
        AVG(HEQ.ViewCount) AS AvgQuestionViewCount,
        AVG(HEQ.AnswerCount) AS AvgQuestionAnswerCount,
        SUM(HEQ.QuestionCommentCount) AS SumQuestionCommentCount,
        SUM(HEQ.TotalAnswerScore) AS SumOfAllAnswerScoresToTheirQuestions
    FROM HighlyEngagingQuestions AS HEQ
    GROUP BY HEQ.OwnerUserId
),
UserAnswerContributions AS (
    SELECT
        A.OwnerUserId AS UserId,
        COUNT(A.Id) AS NumberOfAnswersToHighlyEngagingQuestions,
        AVG(A.Score) AS AvgAnswerScoreToHighlyEngagingQuestions,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScoreOnAnswersGiven
    FROM Posts AS A
    LEFT JOIN Comments AS C ON A.Id = C.PostId
    WHERE A.PostTypeId = 2
      AND A.ParentId IN (SELECT QuestionId FROM HighlyEngagingQuestions)
    GROUP BY A.OwnerUserId
),
QuestionReopenActivity AS (
    SELECT
        PH.PostId AS QuestionId,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 END) AS ClosedCount,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 END) AS ReopenedCount
    FROM PostHistory AS PH
    WHERE PH.PostHistoryTypeId IN (10, 11)
      AND PH.PostId IN (SELECT QuestionId FROM HighlyEngagingQuestions)
    GROUP BY PH.PostId
    HAVING COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 END) > 0
)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.CreationDate AS UserCreationDate,
    U.LastAccessDate,
    U.UpVotes,
    U.DownVotes,
    COALESCE(UBC.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBC.SilverBadges, 0) AS SilverBadges,
    COALESCE(UBC.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(UBC.TotalBadges, 0) AS TotalBadges,
    COALESCE(UQC.NumberOfHighlyEngagingQuestions, 0) AS QuestionsAskedInPopularTags,
    COALESCE(UQC.SumOfQuestionScores, 0) AS TotalQuestionScoreOfOwnQuestions,
    COALESCE(UQC.AvgQuestionViewCount, 0) AS AverageViewCountOfOwnQuestions,
    COALESCE(UQC.SumQuestionCommentCount, 0) AS TotalCommentsOnOwnQuestions,
    COALESCE(UQC.SumOfAllAnswerScoresToTheirQuestions, 0) AS TotalAnswerScoreReceivedOnOwnQuestions,
    COALESCE(UAC.NumberOfAnswersToHighlyEngagingQuestions, 0) AS AnswersToPopularQuestions,
    COALESCE(UAC.AvgAnswerScoreToHighlyEngagingQuestions, 0) AS AvgAnswerScoreToPopularQuestions,
    COALESCE(UAC.TotalCommentScoreOnAnswersGiven, 0) AS TotalCommentScoreOnOwnAnswers,
    COALESCE(SUM(QRA.ReopenedCount), 0) AS TotalQuestionsReopenedOwnedByUser,
    RANK() OVER (
        ORDER BY
            U.Reputation DESC,
            COALESCE(UBC.GoldBadges, 0) DESC,
            COALESCE(UQC.NumberOfHighlyEngagingQuestions, 0) DESC,
            (COALESCE(UAC.AvgAnswerScoreToHighlyEngagingQuestions, 0) * COALESCE(UAC.NumberOfAnswersToHighlyEngagingQuestions, 0)) DESC,
            U.LastAccessDate DESC,
            U.UpVotes DESC
    ) AS UserRank
FROM Users AS U
LEFT JOIN UserBadgeCounts AS UBC ON U.Id = UBC.UserId
LEFT JOIN UserQuestionContributions AS UQC ON U.Id = UQC.UserId
LEFT JOIN UserAnswerContributions AS UAC ON U.Id = UAC.UserId
LEFT JOIN HighlyEngagingQuestions AS HEQ_USER_OWNED ON U.Id = HEQ_USER_OWNED.OwnerUserId
LEFT JOIN QuestionReopenActivity AS QRA ON HEQ_USER_OWNED.QuestionId = QRA.QuestionId
WHERE U.Reputation > 10000
  AND U.LastAccessDate >= DATE '2023-01-01'
  AND (COALESCE(UQC.NumberOfHighlyEngagingQuestions, 0) > 0 OR COALESCE(UAC.NumberOfAnswersToHighlyEngagingQuestions, 0) > 0)
GROUP BY
    U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes,
    UBC.GoldBadges, UBC.SilverBadges, UBC.BronzeBadges, UBC.TotalBadges,
    UQC.NumberOfHighlyEngagingQuestions, UQC.SumOfQuestionScores, UQC.AvgQuestionViewCount,
    UQC.SumQuestionCommentCount, UQC.SumOfAllAnswerScoresToTheirQuestions,
    UAC.NumberOfAnswersToHighlyEngagingQuestions, UAC.AvgAnswerScoreToHighlyEngagingQuestions,
    UAC.TotalCommentScoreOnAnswersGiven
ORDER BY UserRank
LIMIT 200;