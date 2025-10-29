-- {"query": "1785.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4155}
WITH UserQuestionStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT Q.Id) AS TotalQuestionsAsked,
        SUM(Q.Score) AS TotalQuestionScore,
        AVG(Q.ViewCount) AS AvgQuestionViewCount,
        MAX(Q.CreationDate) AS LatestQuestionDate,
        SUM(COALESCE(Q.FavoriteCount, 0)) AS TotalQuestionFavorites,
        COUNT(CASE WHEN Q.ClosedDate IS NOT NULL THEN 1 END) AS QuestionsClosedCount
    FROM Users U
    JOIN Posts Q ON U.Id = Q.OwnerUserId AND Q.PostTypeId = 1
    GROUP BY U.Id, U.DisplayName
    HAVING COUNT(DISTINCT Q.Id) >= 3
),
UserAnswerStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT A.Id) AS TotalAnswersProvided,
        SUM(A.Score) AS TotalAnswerScore,
        AVG(A.Score) AS AvgAnswerScore,
        MAX(A.CreationDate) AS LatestAnswerDate,
        COUNT(CASE WHEN P.AcceptedAnswerId = A.Id THEN 1 END) AS AcceptedAnswersCount
    FROM Users U
    JOIN Posts A ON U.Id = A.OwnerUserId AND A.PostTypeId = 2
    LEFT JOIN Posts P ON A.ParentId = P.Id AND P.PostTypeId = 1
    GROUP BY U.Id, U.DisplayName
    HAVING COUNT(DISTINCT A.Id) >= 5
),
PostEditHistory AS (
    SELECT
        PH.PostId,
        MIN(CASE WHEN PH.PostHistoryTypeId IN (1,2,3) THEN PH.CreationDate END) AS InitialCreationDate,
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.CreationDate END) AS FirstEditDate,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.CreationDate END) AS LastEditDate,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.Id END) AS TotalEdits,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS LastClosedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate END) AS LastReopenedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Comment END) AS LastCloseReasonComment,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Text END) AS LatestCloseVoterJson
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (1,2,3,4,5,6,10,11)
    GROUP BY PH.PostId
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(B.Id) AS TotalBadges
    FROM Badges B
    GROUP BY B.UserId
),
TopQuestionTags AS (
    SELECT
        UserId,
        TagName,
        TagRank
    FROM (
        SELECT
            Q.OwnerUserId AS UserId,
            TRIM(x) AS TagName,
            COUNT(*) AS TagCount,
            ROW_NUMBER() OVER (PARTITION BY Q.OwnerUserId ORDER BY COUNT(*) DESC, TRIM(x) ASC) AS TagRank
        FROM Posts Q,
             UNNEST(string_to_array(substring(Q.Tags from 2 for char_length(Q.Tags) - 2), '><')) AS t(x)
        WHERE Q.PostTypeId = 1 AND Q.Tags IS NOT NULL AND char_length(Q.Tags) > 2
        GROUP BY Q.OwnerUserId, TRIM(x)
    ) AS UserTagCounts
    WHERE TagRank <= 3
),
RecentHighScoreAnswers AS (
    SELECT
        P.ParentId AS QuestionId,
        P.Id AS AnswerId,
        P.Score AS AnswerScore,
        P.OwnerUserId AS AnswerOwnerUserId,
        P.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY P.ParentId ORDER BY P.Score DESC, P.CreationDate DESC) AS rn
    FROM Posts P
    WHERE P.PostTypeId = 2 AND P.Score >= 10
),
UserOverallActivity AS (
    SELECT
        C.UserId,
        MAX(C.CreationDate) AS LastCommentDate,
        COUNT(C.Id) AS TotalComments,
        SUM(C.Score) AS TotalCommentScore,
        NULLIF(
          substring(
            MAX(C.CreationDate || '||' || C.Text) FROM position('||' IN MAX(C.CreationDate || '||' || C.Text)) + 2
          ),
          ''
        ) AS LatestCommentText
    FROM Comments C
    WHERE C.UserId IS NOT NULL
    GROUP BY C.UserId
),
UserActiveEditors AS (
    SELECT DISTINCT PH.UserId
    FROM PostHistory PH
    JOIN Posts P ON PH.PostId = P.Id
    WHERE PH.UserId IS NOT NULL
      AND P.OwnerUserId = PH.UserId
      AND PH.PostHistoryTypeId IN (4,5,6)
)
SELECT
    'Questioner' AS UserRole,
    U.Id AS UserIdentifier,
    U.DisplayName,
    U.Reputation,
    U.CreationDate AS UserRegistrationDate,
    U.LastAccessDate,
    U.Views AS UserProfileViews,
    U.UpVotes AS UserTotalUpVotes,
    U.DownVotes AS UserTotalDownVotes,
    UQS.TotalQuestionsAsked,
    UQS.TotalQuestionScore,
    UQS.AvgQuestionViewCount,
    UQS.LatestQuestionDate,
    UQS.TotalQuestionFavorites,
    UQS.QuestionsClosedCount,
    NULL AS TotalAnswersProvided,
    NULL AS TotalAnswerScore,
    NULL AS AvgAnswerScore,
    NULL AS LatestAnswerDate,
    NULL AS AcceptedAnswersCount,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadgesCount,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadgesCount,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadgesCount,
    UBS.TotalBadges,
    (SELECT TT.TagName FROM TopQuestionTags TT WHERE TT.UserId = U.Id AND TT.TagRank = 1) AS TopTag1,
    (SELECT TT.TagName FROM TopQuestionTags TT WHERE TT.UserId = U.Id AND TT.TagRank = 2) AS TopTag2,
    (SELECT TT.TagName FROM TopQuestionTags TT WHERE TT.UserId = U.Id AND TT.TagRank = 3) AS TopTag3,
    UOA.TotalComments,
    UOA.TotalCommentScore,
    UOA.LatestCommentText,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - U.CreationDate))/3600/24 AS UserAgeInDays,
    CASE
        WHEN U.Reputation > 15000 AND UQS.TotalQuestionsAsked > 50 THEN 'Guru Questioner'
        WHEN U.Reputation > 7500 OR UQS.TotalQuestionScore > 1000 THEN 'Proactive Questioner'
        ELSE 'Regular Questioner'
    END AS UserCategory,
    P.Id AS ExamplePostId,
    P.Title AS ExamplePostTitle,
    P.CreationDate AS ExamplePostCreationDate,
    PEH.TotalEdits AS ExamplePostTotalEdits,
    PEH.LastEditDate AS ExamplePostLastEditDate,
    PEH.LastClosedDate AS ExamplePostLastClosedDate,
    PEH.LastReopenedDate AS ExamplePostLastReopenedDate,
    PEH.LastCloseReasonComment AS ExamplePostLastCloseReason,
    PEH.LatestCloseVoterJson AS ExamplePostCloseVoterDetails,
    COALESCE(P.AcceptedAnswerId, -1) AS AcceptedAnswerIdForPost,
    AA.Score AS AcceptedAnswerScore,
    AA.OwnerDisplayName AS AcceptedAnswerOwnerDisplayName,
    (
        SELECT AVG(InnerA.Score)
        FROM Posts InnerA
        WHERE InnerA.ParentId = P.Id
          AND InnerA.PostTypeId = 2
          AND InnerA.CreationDate > P.CreationDate
          AND InnerA.OwnerUserId IS NOT NULL
          AND EXISTS (SELECT 1 FROM Users InnerU WHERE InnerU.Id = InnerA.OwnerUserId AND InnerU.Reputation > 1000)
    ) AS AvgHighRepAnswerScoreForPost,
    (
        SELECT COUNT(DISTINCT PH2.UserId)
        FROM PostHistory PH2
        WHERE PH2.PostId = P.Id
          AND PH2.PostHistoryTypeId IN (4,5,6)
          AND PH2.CreationDate > P.CreationDate + INTERVAL '2 months'
    ) AS EditorsAfterTwoMonthsCount,
    CASE
        WHEN P.ClosedDate IS NOT NULL AND PEH.LastReopenedDate IS NOT NULL AND PEH.LastReopenedDate > P.ClosedDate THEN 'Reopened_Q'
        WHEN P.ClosedDate IS NOT NULL THEN 'Closed_Q'
        ELSE 'Open_Q'
    END AS PostStatus,
    RHS.AnswerId AS TopRelatedAnswerId,
    RHS.AnswerScore AS TopRelatedAnswerScore,
    RHS.AnswerOwnerUserId AS TopRelatedAnswerOwner
FROM Users U
INNER JOIN UserQuestionStats UQS ON U.Id = UQS.UserId
LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
LEFT JOIN UserOverallActivity UOA ON U.Id = UOA.UserId
LEFT JOIN Posts P ON U.Id = P.OwnerUserId AND P.PostTypeId = 1 AND P.Score > 50 AND P.ViewCount > 5000 AND P.AnswerCount > 3
LEFT JOIN PostEditHistory PEH ON P.Id = PEH.PostId
LEFT JOIN Posts AA ON P.AcceptedAnswerId = AA.Id AND AA.PostTypeId = 2
LEFT JOIN RecentHighScoreAnswers RHS ON P.Id = RHS.QuestionId AND RHS.rn = 1
WHERE U.Reputation > 5000
  AND U.LastAccessDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
  AND ((U.Location IS NOT NULL AND U.Location LIKE '%USA%') OR U.WebsiteUrl IS NOT NULL)
  AND U.Id IN (SELECT UserId FROM UserActiveEditors)
  AND (UOA.TotalComments IS DISTINCT FROM 0)
  AND UOA.TotalComments > 5
  AND char_length(COALESCE(U.AboutMe, '')) > 100

UNION ALL

SELECT
    'Answerer' AS UserRole,
    U.Id AS UserIdentifier,
    U.DisplayName,
    U.Reputation,
    U.CreationDate AS UserRegistrationDate,
    U.LastAccessDate,
    U.Views AS UserProfileViews,
    U.UpVotes AS UserTotalUpVotes,
    U.DownVotes AS UserTotalDownVotes,
    NULL AS TotalQuestionsAsked,
    NULL AS TotalQuestionScore,
    NULL AS AvgQuestionViewCount,
    NULL AS LatestQuestionDate,
    NULL AS TotalQuestionFavorites,
    NULL AS QuestionsClosedCount,
    UAS.TotalAnswersProvided,
    UAS.TotalAnswerScore,
    UAS.AvgAnswerScore,
    UAS.LatestAnswerDate,
    UAS.AcceptedAnswersCount,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadgesCount,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadgesCount,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadgesCount,
    UBS.TotalBadges,
    NULL AS TopTag1,
    NULL AS TopTag2,
    NULL AS TopTag3,
    UOA.TotalComments,
    UOA.TotalCommentScore,
    UOA.LatestCommentText,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - U.CreationDate))/3600/24 AS UserAgeInDays,
    CASE
        WHEN U.Reputation > 20000 AND UAS.AcceptedAnswersCount > 20 THEN 'Legendary Answerer'
        WHEN U.Reputation > 10000 OR UAS.TotalAnswerScore > 2000 THEN 'Expert Answerer'
        ELSE 'Contributor Answerer'
    END AS UserCategory,
    A.Id AS ExamplePostId,
    A.Body AS ExamplePostTitle,
    A.CreationDate AS ExamplePostCreationDate,
    PEH.TotalEdits AS ExamplePostTotalEdits,
    PEH.LastEditDate AS ExamplePostLastEditDate,
    NULL AS ExamplePostLastClosedDate,
    NULL AS ExamplePostLastReopenedDate,
    NULL AS ExamplePostLastCloseReason,
    NULL AS ExamplePostCloseVoterDetails,
    NULL AS AcceptedAnswerIdForPost,
    A.Score AS AcceptedAnswerScore,
    U.DisplayName AS AcceptedAnswerOwnerDisplayName,
    (
        SELECT COUNT(DISTINCT C.Id)
        FROM Comments C
        WHERE C.PostId = A.Id
          AND C.CreationDate > A.CreationDate
          AND C.Score > 0
    ) AS AvgHighRepAnswerScoreForPost,
    (
        SELECT COUNT(DISTINCT V.UserId)
        FROM Votes V
        WHERE V.PostId = A.Id
          AND V.VoteTypeId = 2
          AND V.CreationDate >= A.CreationDate + INTERVAL '1 week'
    ) AS EditorsAfterTwoMonthsCount,
    CASE
        WHEN A.ParentId IS NOT NULL AND (SELECT P_q.AcceptedAnswerId FROM Posts P_q WHERE P_q.Id = A.ParentId) = A.Id THEN 'Accepted_A'
        WHEN A.Score > 50 THEN 'High_Score_A'
        ELSE 'Regular_A'
    END AS PostStatus,
    NULL AS TopRelatedAnswerId,
    NULL AS TopRelatedAnswerScore,
    NULL AS TopRelatedAnswerOwner
FROM Users U
INNER JOIN UserAnswerStats UAS ON U.Id = UAS.UserId
LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
LEFT JOIN UserOverallActivity UOA ON U.Id = UOA.UserId
LEFT JOIN Posts A ON U.Id = A.OwnerUserId AND A.PostTypeId = 2 AND A.Score > 75 AND A.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years'
LEFT JOIN PostEditHistory PEH ON A.Id = PEH.PostId
WHERE U.Reputation > 7500
  AND U.LastAccessDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
  AND (U.Location IS NOT NULL AND U.Location LIKE '%USA%')
  AND U.Id IN (SELECT UserId FROM UserActiveEditors)
  AND UOA.TotalComments > 20
  AND U.WebsiteUrl IS NOT NULL
ORDER BY Reputation DESC, UserTotalUpVotes DESC, UserAgeInDays ASC
LIMIT 2000;