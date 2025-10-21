WITH RelevantTags AS (
    SELECT TagName
    FROM Tags
    WHERE TagName IN ('sql', 'postgresql', 'database', 'performance', 'indexing', 'query-optimization', 'bigquery', 'sql-server', 'mysql', 'oracle', 'nosql', 'mongodb', 'redis', 'elasticsearch')
),
PopularQuestionsWithTags AS (
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId AS QuestionOwnerUserId,
        P.Score AS QuestionScore,
        P.ViewCount AS QuestionViewCount,
        P.CreationDate AS QuestionCreationDate,
        P.AcceptedAnswerId,
        P.Tags
    FROM Posts P
    WHERE P.PostTypeId = 1 -- Questions
      AND P.Score >= 75 -- Only highly scored questions
      AND P.ViewCount >= 5000 -- Only widely viewed questions
      AND P.AnswerCount > 0 -- Must have at least one answer
      AND EXISTS (
          SELECT 1
          FROM RelevantTags RT
          WHERE RT.TagName = ANY(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><'))
      )
),
UserAnswerContributions AS (
    SELECT
        A.OwnerUserId AS ContributorUserId,
        COUNT(DISTINCT A.Id) AS TotalAnswersToPopularQuestions,
        SUM(A.Score) AS TotalAnswerScoreToPopularQuestions,
        COUNT(DISTINCT CASE WHEN A.Id = PQT.AcceptedAnswerId THEN A.Id END) AS AcceptedAnswersToPopularQuestionsCount,
        SUM(CASE WHEN A.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year' THEN 1 ELSE 0 END) AS RecentAnswersToPopularQuestionsCount,
        MAX(A.LastActivityDate) AS LastAnswerActivityToPopularQuestions
    FROM Posts A -- Answers
    JOIN PopularQuestionsWithTags PQT ON A.ParentId = PQT.QuestionId
    WHERE A.PostTypeId = 2 -- Answers
      AND A.OwnerUserId IS NOT NULL
    GROUP BY A.OwnerUserId
),
UserCommentActivitySummary AS (
    SELECT
        C.UserId AS CommenterUserId,
        COUNT(C.Id) AS TotalCommentsMade,
        SUM(C.Score) AS TotalCommentScore,
        COUNT(CASE WHEN C.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months' THEN 1 ELSE 0 END) AS RecentCommentsMadeCount
    FROM Comments C
    WHERE C.UserId IS NOT NULL
    GROUP BY C.UserId
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadgesCount,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadgesCount,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadgesCount,
        MAX(B.Date) AS LastBadgeAwardDate
    FROM Badges B
    GROUP BY B.UserId
),
UserPostHistoryEdits AS (
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS TotalEditsCount,
        COUNT(DISTINCT PH.PostId) AS UniquePostsEditedCount,
        MAX(PH.CreationDate) AS LastEditDate
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24) -- Edit Title, Edit Body, Edit Tags, Rollback Body/Tags, Suggested Edit Applied
      AND PH.UserId IS NOT NULL
    GROUP BY PH.UserId
),
UserQuestionContributions AS (
    SELECT
        Q.OwnerUserId,
        COUNT(Q.Id) AS TotalQuestionsAsked,
        SUM(Q.Score) AS TotalQuestionScore,
        COUNT(CASE WHEN Q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        SUM(CASE WHEN Q.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year' THEN 1 ELSE 0 END) AS RecentQuestionsAsked
    FROM Posts Q
    WHERE Q.PostTypeId = 1 -- Questions
      AND Q.OwnerUserId IS NOT NULL
    GROUP BY Q.OwnerUserId
)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.UpVotes AS TotalUpVotesGiven,
    U.DownVotes AS TotalDownVotesGiven,
    U.Views AS ProfileViews,
    U.CreationDate AS UserCreationDate,
    U.LastAccessDate AS UserLastAccessDate,

    COALESCE(UAC.TotalAnswersToPopularQuestions, 0) AS ContributedAnswersToPopularQuestions,
    COALESCE(UAC.TotalAnswerScoreToPopularQuestions, 0) AS ScoreFromPopularAnswers,
    COALESCE(UAC.AcceptedAnswersToPopularQuestionsCount, 0) AS AcceptedAnswersInPopularQuestions,
    CAST(COALESCE(UAC.AcceptedAnswersToPopularQuestionsCount, 0) AS DECIMAL) * 100.0 / NULLIF(COALESCE(UAC.TotalAnswersToPopularQuestions, 0), 0) AS AnswerAcceptanceRateForPopularQs,
    COALESCE(UAC.RecentAnswersToPopularQuestionsCount, 0) AS RecentAnswersToPopularQs,
    COALESCE(UAC.LastAnswerActivityToPopularQuestions, TIMESTAMP '1900-01-01 00:00:00') AS LastAnswerContributionDate,

    COALESCE(UCS.TotalCommentsMade, 0) AS TotalComments,
    COALESCE(UCS.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(UCS.RecentCommentsMadeCount, 0) AS RecentComments,

    COALESCE(UBS.GoldBadgesCount, 0) AS GoldBadges,
    COALESCE(UBS.SilverBadgesCount, 0) AS SilverBadges,
    COALESCE(UBS.BronzeBadgesCount, 0) AS BronzeBadges,
    COALESCE(UBS.LastBadgeAwardDate, TIMESTAMP '1900-01-01 00:00:00') AS LastBadgeAwardDate,

    COALESCE(UPE.TotalEditsCount, 0) AS TotalEdits,
    COALESCE(UPE.UniquePostsEditedCount, 0) AS UniquePostsEdited,
    COALESCE(UPE.LastEditDate, TIMESTAMP '1900-01-01 00:00:00') AS LastEditContributionDate,

    COALESCE(UQC.TotalQuestionsAsked, 0) AS TotalQuestionsAsked,
    COALESCE(UQC.TotalQuestionScore, 0) AS TotalQuestionScore,
    COALESCE(UQC.QuestionsWithAcceptedAnswer, 0) AS QuestionsWithAcceptedAnswer,
    COALESCE(UQC.RecentQuestionsAsked, 0) AS RecentQuestionsAsked,

    -- Calculate a comprehensive weighted score for ranking
    (U.Reputation * 0.4) +
    (COALESCE(UAC.TotalAnswerScoreToPopularQuestions, 0) * 0.3) +
    (COALESCE(UAC.AcceptedAnswersToPopularQuestionsCount, 0) * 100) + -- High value for accepted answers
    (COALESCE(UAC.RecentAnswersToPopularQuestionsCount, 0) * 15) +
    (COALESCE(UBS.GoldBadgesCount, 0) * 300) +
    (COALESCE(UBS.SilverBadgesCount, 0) * 75) +
    (COALESCE(UBS.BronzeBadgesCount, 0) * 15) +
    (COALESCE(UPE.TotalEditsCount, 0) * 2) +
    (COALESCE(UQC.TotalQuestionScore, 0) * 0.1) +
    (COALESCE(UQC.QuestionsWithAcceptedAnswer, 0) * 20) +
    (COALESCE(UCS.TotalCommentScore, 0) * 0.5)
    AS WeightedContributionScore,

    RANK() OVER (ORDER BY
        (U.Reputation * 0.4) +
        (COALESCE(UAC.TotalAnswerScoreToPopularQuestions, 0) * 0.3) +
        (COALESCE(UAC.AcceptedAnswersToPopularQuestionsCount, 0) * 100) +
        (COALESCE(UAC.RecentAnswersToPopularQuestionsCount, 0) * 15) +
        (COALESCE(UBS.GoldBadgesCount, 0) * 300) +
        (COALESCE(UBS.SilverBadgesCount, 0) * 75) +
        (COALESCE(UBS.BronzeBadgesCount, 0) * 15) +
        (COALESCE(UPE.TotalEditsCount, 0) * 2) +
        (COALESCE(UQC.TotalQuestionScore, 0) * 0.1) +
        (COALESCE(UQC.QuestionsWithAcceptedAnswer, 0) * 20) +
        (COALESCE(UCS.TotalCommentScore, 0) * 0.5)
        DESC, U.LastAccessDate DESC) AS OverallRank
FROM Users U
LEFT JOIN UserAnswerContributions UAC ON U.Id = UAC.ContributorUserId
LEFT JOIN UserCommentActivitySummary UCS ON U.Id = UCS.CommenterUserId
LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
LEFT JOIN UserPostHistoryEdits UPE ON U.Id = UPE.UserId
LEFT JOIN UserQuestionContributions UQC ON U.Id = UQC.OwnerUserId
WHERE U.Reputation > 5000 -- Focus on highly reputable users
  AND (UAC.ContributorUserId IS NOT NULL OR UCS.CommenterUserId IS NOT NULL OR UPE.UserId IS NOT NULL OR UQC.OwnerUserId IS NOT NULL) -- Ensure user has some form of contribution
  AND U.LastAccessDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1.5 years' -- Only consider recently active users
ORDER BY OverallRank
LIMIT 200;