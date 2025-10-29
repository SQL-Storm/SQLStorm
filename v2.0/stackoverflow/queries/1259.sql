WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.DisplayName,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScoreReceived,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViewsReceived,
        SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL AND P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        SUM(CASE WHEN P.PostTypeId = 2 AND P.Id = QP.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswersGiven,
        MAX(P.CreationDate) AS LastPostCreationDate,
        MAX(C.CreationDate) AS LastCommentCreationDate,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE NULL END) AS AvgQuestionViews,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE NULL END) AS AvgAnswerScore
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Posts QP ON P.ParentId = QP.Id
    GROUP BY U.Id, U.Reputation, U.DisplayName, U.CreationDate, U.LastAccessDate
),
PostHistorySummary AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        MAX(PH.CreationDate) AS LastHistoryDate,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.Id END) AS EditCount,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (10, 11, 12, 13) THEN PH.PostHistoryTypeId ELSE NULL END) AS LastModActionType,
        STRING_AGG(DISTINCT SUBSTRING(PHT.Name FROM 1 FOR 10), ',') AS RecentHistoryTypeNames
    FROM PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE PH.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY PH.PostId
),
TagPerformanceMetrics AS (
    SELECT
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><'))) AS TagName,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.Id AS PostId,
        P.OwnerUserId AS OwnerUserId
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
AggregatedTagStats AS (
    SELECT
        TPM.TagName,
        COUNT(TPM.PostScore) AS TaggedPostCount,
        AVG(TPM.PostScore) AS AvgTagScore,
        AVG(TPM.PostViewCount) AS AvgTagViewCount,
        SUM(CASE WHEN TPM.PostScore > 0 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(TPM.PostScore), 0) AS PositiveScorePercentage
    FROM TagPerformanceMetrics TPM
    GROUP BY TPM.TagName
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(CASE WHEN B.Class = 1 THEN B.Date ELSE NULL END) AS LastGoldBadgeDate
    FROM Badges B
    GROUP BY B.UserId
),
CorrelatedPostMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId AS UserId,
        P.Score AS CurrentPostScore,
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING) AS AvgPrev5PostScore,
        (
         SELECT AVG(PS.Score)
         FROM Posts PS
         JOIN PostLinks PL_sub ON PS.Id = PL_sub.RelatedPostId
         WHERE PL_sub.PostId = P.Id AND PL_sub.LinkTypeId = 1
        ) AS AvgLinkedRelatedPostScore
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
)
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.UserCreationDate,
    UE.LastAccessDate,
    UE.TotalPosts,
    UE.TotalQuestions,
    UE.TotalAnswers,
    UE.TotalComments,
    UE.TotalPostScoreReceived,
    UE.TotalPostViewsReceived,
    UE.QuestionsWithAcceptedAnswer,
    UE.AcceptedAnswersGiven,
    UE.AvgQuestionViews,
    UE.AvgAnswerScore,
    UBS.TotalBadges,
    UBS.GoldBadges,
    UBS.SilverBadges,
    UBS.BronzeBadges,
    UBS.LastGoldBadgeDate,
    ROUND(CAST(UE.TotalPosts AS NUMERIC) / NULLIF(EXTRACT(EPOCH FROM (UE.LastAccessDate - UE.UserCreationDate)) / (60 * 60 * 24), 0), 4) AS PostsPerDaySinceCreation,
    ROUND(CAST(UE.AcceptedAnswersGiven AS NUMERIC) / NULLIF(UE.TotalAnswers, 0), 4) AS AcceptedAnswerRatio,
    ROUND(CAST(UE.QuestionsWithAcceptedAnswer AS NUMERIC) / NULLIF(UE.TotalQuestions, 0), 4) AS QuestionAcceptanceRate,
    COALESCE(UBS.GoldBadges, 0) * 1.0 + COALESCE(UBS.SilverBadges, 0) * 0.5 + COALESCE(UBS.BronzeBadges, 0) * 0.2 AS WeightedBadgeScore,
    (SELECT P.Title FROM Posts P WHERE P.OwnerUserId = UE.UserId ORDER BY P.Score DESC, P.CreationDate DESC LIMIT 1) AS TopPostTitle,
    (SELECT P.Score FROM Posts P WHERE P.OwnerUserId = UE.UserId ORDER BY P.Score DESC, P.CreationDate DESC LIMIT 1) AS TopPostScore,
    (SELECT P.Id FROM Posts P WHERE P.OwnerUserId = UE.UserId ORDER BY P.Score DESC, P.CreationDate DESC LIMIT 1) AS TopPostId,
    COALESCE((SELECT AVG(PHS.EditCount)
             FROM Posts P_sub
             JOIN PostHistorySummary PHS ON P_sub.Id = PHS.PostId
             WHERE P_sub.OwnerUserId = UE.UserId), 0) AS AvgPostEditCount,
    (SELECT AVG(CPM.AvgPrev5PostScore) FROM CorrelatedPostMetrics CPM WHERE CPM.UserId = UE.UserId) AS UserAvgPrev5PostScore,
    (SELECT AVG(CPM.AvgLinkedRelatedPostScore) FROM CorrelatedPostMetrics CPM WHERE CPM.UserId = UE.UserId AND CPM.AvgLinkedRelatedPostScore IS NOT NULL) AS UserAvgScoreOfLinkedPosts,
    NTILE(10) OVER (ORDER BY UE.Reputation DESC) AS ReputationDecile,
    RANK() OVER (ORDER BY UE.TotalPostScoreReceived DESC, UE.TotalPosts DESC, UE.LastAccessDate DESC) AS GlobalInfluenceRank,
    UPPER(SUBSTRING(COALESCE(UE.DisplayName, 'ANON') FROM 1 FOR 5)) || '_' ||
    MD5(COALESCE(U.Location, 'N/A') || COALESCE(U.AboutMe, '')) AS UserHashIdentifier,
    CASE
        WHEN UE.Reputation >= 20000 AND COALESCE(UBS.GoldBadges, 0) > 0 THEN 'Legendary Contributor'
        WHEN UE.Reputation >= 10000 AND UE.TotalPosts > 100 THEN 'Elite Member'
        WHEN UE.Reputation >= 5000 AND UE.TotalAnswers > 50 AND UE.AcceptedAnswersGiven > 10 THEN 'Seasoned Expert'
        WHEN UE.Reputation >= 1000 AND UE.TotalPosts > 10 AND UE.LastAccessDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months' THEN 'Active Participant'
        WHEN UE.Reputation > 1 THEN 'Novice Contributor'
        ELSE 'Passive User'
    END AS UserCategory,
    (SELECT AVG(Reputation) FROM Users WHERE CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 year') AS AvgRecentCommunityReputation,
    (SELECT SUM(CASE WHEN P_all.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) FROM Posts P_all WHERE P_all.PostTypeId = 1) * 100.0 / NULLIF((SELECT COUNT(Id) FROM Posts WHERE PostTypeId = 1), 0) AS CommunityQuestionClosedRate,
    (SELECT AVG(ATS.AvgTagScore)
     FROM AggregatedTagStats ATS
     JOIN TagPerformanceMetrics TPM_sub ON ATS.TagName = TPM_sub.TagName
     WHERE TPM_sub.OwnerUserId IN (SELECT P_tag.OwnerUserId FROM Posts P_tag WHERE P_tag.OwnerUserId = UE.UserId)
     GROUP BY ATS.TagName
     ORDER BY COUNT(TPM_sub.PostId) DESC
     LIMIT 1
    ) AS AvgScoreOfMostFrequentTag
FROM UserEngagement UE
LEFT JOIN Users U ON UE.UserId = U.Id
LEFT JOIN UserBadgeSummary UBS ON UE.UserId = UBS.UserId
WHERE UE.Reputation > 1
  AND UE.LastAccessDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 year'
ORDER BY UE.Reputation DESC, UE.TotalPostScoreReceived DESC, UE.LastAccessDate DESC
LIMIT 1000;