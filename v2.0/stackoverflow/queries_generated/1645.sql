-- {"query": "1645.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3334} 
WITH UserEngagementStats AS (
    SELECT
        U.Id AS UserId,
        COUNT(P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalQuestionViews,
        COUNT(C.Id) AS TotalComments,
        MAX(P.LastActivityDate) AS LatestPostActivity,
        MIN(P.CreationDate) AS FirstPostDate,
        SUM(CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        SUM(CASE WHEN P.PostTypeId = 2 AND P.Id = (SELECT Q.AcceptedAnswerId FROM Posts Q WHERE Q.Id = P.ParentId) THEN 1 ELSE 0 END) AS AcceptedAnswersCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id
),
UserBadgeSummary AS (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN Id END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN Id END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN Id END) AS BronzeBadges,
        COUNT(CASE WHEN TagBased = TRUE THEN Id END) AS TagBasedBadges
    FROM Badges
    GROUP BY UserId
),
PostEditActivity AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS LastClosedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 16 THEN PH.CreationDate END) AS CommunityOwnedDateHistory,
        MIN(LENGTH(PH.Text)) FILTER (WHERE PH.PostHistoryTypeId IN (2, 5, 8)) AS MinBodyLength,
        MAX(LENGTH(PH.Text)) FILTER (WHERE PH.PostHistoryTypeId IN (2, 5, 8)) AS MaxBodyLength,
        COUNT(DISTINCT PH.UserId) AS UniqueEditors,
        MAX(PH.CreationDate) AS LatestHistoryEventDate,
        LAG(PH.Text, 1, '') OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousText
    FROM PostHistory PH
    GROUP BY PH.PostId, PH.CreationDate, PH.Text
),
QuestionDetailedMetrics AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.AnswerCount,
        Q.FavoriteCount,
        Q.AcceptedAnswerId,
        Q.Title AS QuestionTitle,
        Q.Tags,
        (SELECT COUNT(P.Id) FROM Posts P WHERE P.ParentId = Q.Id AND P.OwnerUserId = Q.OwnerUserId) AS SelfAnswersCount,
        COALESCE(Q.FavoriteCount, 0) * 1.0 / NULLIF(Q.ViewCount, 0) AS FavoriteToViewRatio,
        Q.ClosedDate IS NOT NULL AS IsClosed,
        MAX(V.CreationDate) FILTER (WHERE V.VoteTypeId = 2) AS LatestUpvoteDate,
        AVG(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteFrequency
    FROM Posts Q
    LEFT JOIN Votes V ON Q.Id = V.PostId
    WHERE Q.PostTypeId = 1
    GROUP BY Q.Id, Q.OwnerUserId, Q.CreationDate, Q.Score, Q.ViewCount, Q.AnswerCount, Q.FavoriteCount, Q.AcceptedAnswerId, Q.Title, Q.Tags, Q.ClosedDate
),
AnswerDetailedMetrics AS (
    SELECT
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.OwnerUserId,
        A.CreationDate AS AnswerCreationDate,
        A.Score AS AnswerScore,
        A.LastEditDate AS AnswerLastEditDate,
        (A.Id = Q.AcceptedAnswerId) AS IsAccepted,
        ROW_NUMBER() OVER (PARTITION BY A.ParentId ORDER BY A.Score DESC, A.CreationDate ASC) AS RankByScoreForQuestion
    FROM Posts A
    INNER JOIN Posts Q ON A.ParentId = Q.Id
    WHERE A.PostTypeId = 2
),
TagPerformancePerUser AS (
    SELECT
        P.OwnerUserId AS UserId,
        TRIM(unnest(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'))) AS TagName,
        COUNT(DISTINCT P.Id) AS QuestionsWithTag,
        SUM(P.Score) AS TotalTagScore,
        AVG(P.Score) AS AvgTagScore,
        RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY SUM(P.Score) DESC, COUNT(DISTINCT P.Id) DESC, MAX(P.CreationDate) DESC) AS TagRankForUser
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    GROUP BY P.OwnerUserId, TRIM(unnest(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')))
    HAVING COUNT(DISTINCT P.Id) >= 5
),
UserMetricsAggregated AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.Views AS ProfileViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COALESCE(UES.TotalPosts, 0) AS UserTotalPosts,
        COALESCE(UES.TotalPostScore, 0) AS UserTotalPostScore,
        COALESCE(UES.TotalQuestions, 0) AS UserQuestions,
        COALESCE(UES.TotalAnswers, 0) AS UserAnswers,
        COALESCE(UES.AcceptedAnswersCount, 0) AS UserAcceptedAnswers,
        COALESCE(UBS.GoldBadges, 0) AS UserGoldBadges,
        COALESCE(UBS.SilverBadges, 0) AS UserSilverBadges,
        COALESCE(UBS.BronzeBadges, 0) AS UserBronzeBadges,
        UES.LatestPostActivity,
        NTILE(10) OVER (ORDER BY U.Reputation DESC, U.UpVotes DESC, U.CreationDate ASC) AS ReputationDecile,
        RANK() OVER (ORDER BY U.Reputation DESC, U.UpVotes DESC, U.DownVotes ASC, UES.TotalPostScore DESC) AS GlobalRepRank
    FROM Users U
    LEFT JOIN UserEngagementStats UES ON U.Id = UES.UserId
    LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
    WHERE U.Reputation > 1000
    AND U.DisplayName IS NOT NULL AND LENGTH(U.DisplayName) > 0
    AND U.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
),
TopQuestionUsers AS (
    SELECT
        UMA.UserId,
        UMA.DisplayName,
        UMA.Reputation,
        'Top Questions Contributor' AS UserCategory,
        (SELECT COUNT(Q.QuestionId) FROM QuestionDetailedMetrics Q WHERE Q.OwnerUserId = UMA.UserId AND Q.FavoriteToViewRatio > 0.01) AS HighFavoriteRatioQuestions,
        (SELECT MAX(Q.QuestionScore) FROM QuestionDetailedMetrics Q WHERE Q.OwnerUserId = UMA.UserId) AS MaxQuestionScore
    FROM UserMetricsAggregated UMA
    WHERE UMA.UserQuestions > 50 AND UMA.UserTotalPostScore > 500
),
TopAnswerUsers AS (
    SELECT
        UMA.UserId,
        UMA.DisplayName,
        UMA.Reputation,
        'Top Answers Contributor' AS UserCategory,
        UMA.UserAcceptedAnswers AS AcceptedAnswers,
        (SELECT AVG(A.AnswerScore) FROM AnswerDetailedMetrics A WHERE A.OwnerUserId = UMA.UserId) AS AvgAnswerScore
    FROM UserMetricsAggregated UMA
    WHERE UMA.UserAnswers > 20 AND UMA.UserAcceptedAnswers > 5
)
SELECT
    CombinedUsers.UserId,
    CombinedUsers.DisplayName,
    CombinedUsers.Reputation,
    CombinedUsers.UserCategory,
    UMA.ReputationDecile,
    UMA.GlobalRepRank,
    UMA.UserTotalPosts,
    UMA.UserTotalPostScore,
    UMA.UserQuestions,
    UMA.UserAnswers,
    UMA.UserAcceptedAnswers,
    UMA.UserGoldBadges,
    UMA.UserSilverBadges,
    UMA.UserBronzeBadges,
    AGE(CURRENT_TIMESTAMP, UMA.CreationDate) AS AccountAge,
    EXTRACT(WEEK FROM UMA.LatestPostActivity) AS LastActivityWeekOfYear,
    COALESCE(QDM_Agg.AvgQuestionScore, 0.0) AS AvgQuestionScore,
    COALESCE(QDM_Agg.AvgQuestionViewCount, 0.0) AS AvgQuestionViewCount,
    COALESCE(QDM_Agg.MaxQuestionScore, 0) AS MaxQuestionScoreEver,
    COALESCE(ADM_Agg.AvgAnswerScore, 0.0) AS AvgAnswerScore,
    COALESCE(ADM_Agg.TotalAcceptedAnswers, 0) AS TotalAcceptedAnswers,
    COALESCE(PHA_Agg.AvgEditCountPerPost, 0.0) AS AvgEditCountPerPost,
    COALESCE(TPPUser.TopTag, 'N/A') AS MostInfluentialTag,
    COALESCE(TPPUser.TopTagScore, 0) AS MostInfluentialTagScore,
    (
        SELECT COUNT(DISTINCT PH.PostId)
        FROM PostHistory PH
        WHERE PH.UserId = CombinedUsers.UserId
          AND PH.PostHistoryTypeId IN (10, 12) -- Post Closed or Post Deleted
          AND PH.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '1 year')
    ) AS RecentModerationActionsByOwner,
    (
        SELECT COALESCE(SUM(CASE WHEN LT.LinkTypeId = 3 THEN 1 ELSE 0 END), 0)
        FROM PostLinks PL
        INNER JOIN LinkTypes LT ON PL.LinkTypeId = LT.Id
        WHERE PL.PostId IN (SELECT Q.QuestionId FROM QuestionDetailedMetrics Q WHERE Q.OwnerUserId = CombinedUsers.UserId)
    ) AS TotalDuplicateLinksFromQuestions,
    (
        SELECT STRING_AGG(DISTINCT T.TagName, ', ')
        FROM Tags T
        WHERE T.TagName LIKE 'java%'
        AND T.Id IN (
            SELECT CAST(UNNEST(STRING_TO_ARRAY(SUBSTRING(P_TAG.Tags, 2, LENGTH(P_TAG.Tags)-2), '><')) AS varchar)
            FROM Posts P_TAG
            WHERE P_TAG.OwnerUserId = CombinedUsers.UserId
            AND P_TAG.PostTypeId = 1
            AND P_TAG.Score > 100
            LIMIT 5
        )
    ) AS HighScoreJavaRelatedTags,
    CASE
        WHEN UMA.UserGoldBadges >= 3 AND UMA.Reputation > 50000 THEN 'Elite Developer'
        WHEN UMA.UserAcceptedAnswers >= 10 AND UMA.UserTotalPostScore > 1000 THEN 'Key Contributor'
        WHEN UMA.UserQuestions > 20 AND UMA.AvgQuestionScore > 15 THEN 'Question Master'
        ELSE 'Engaged User'
    END AS UserPersona
FROM (
    SELECT UserId, DisplayName, Reputation, UserCategory FROM TopQuestionUsers
    UNION ALL
    SELECT UserId, DisplayName, Reputation, UserCategory FROM TopAnswerUsers
) AS CombinedUsers
INNER JOIN UserMetricsAggregated UMA ON CombinedUsers.UserId = UMA.UserId
LEFT JOIN (
    SELECT
        OwnerUserId,
        COUNT(QuestionId) AS QuestionCount,
        AVG(QuestionScore) AS AvgQuestionScore,
        AVG(ViewCount) AS AvgQuestionViewCount,
        MAX(QuestionScore) AS MaxQuestionScore
    FROM QuestionDetailedMetrics
    GROUP BY OwnerUserId
) AS QDM_Agg ON CombinedUsers.UserId = QDM_Agg.OwnerUserId
LEFT JOIN (
    SELECT
        OwnerUserId,
        AVG(AnswerScore) AS AvgAnswerScore,
        MAX(AnswerScore) AS MaxAnswerScore,
        COUNT(CASE WHEN IsAccepted THEN 1 END) AS TotalAcceptedAnswers
    FROM AnswerDetailedMetrics
    GROUP BY OwnerUserId
) AS ADM_Agg ON CombinedUsers.UserId = ADM_Agg.OwnerUserId
LEFT JOIN (
    SELECT
        P.OwnerUserId,
        AVG(PHA.EditCount) AS AvgEditCountPerPost
    FROM Posts P
    INNER JOIN PostEditActivity PHA ON P.Id = PHA.PostId
    GROUP BY P.OwnerUserId
) AS PHA_Agg ON CombinedUsers.UserId = PHA_Agg.OwnerUserId
LEFT JOIN (
    SELECT
        UserId,
        TagName AS TopTag,
        TotalTagScore AS TopTagScore,
        QuestionsWithTag AS TopTagQuestionCount
    FROM TagPerformancePerUser
    WHERE TagRankForUser = 1
) AS TPPUser ON CombinedUsers.UserId = TPPUser.UserId
WHERE UMA.GlobalRepRank <= 2000
  AND (UMA.ProfileViews > 100 OR UMA.UserTotalPosts > 100)
  AND (UMA.UserGoldBadges > 0 OR UMA.UserAcceptedAnswers > 3)
  AND UMA.LatestPostActivity > (CURRENT_TIMESTAMP - INTERVAL '1 year 6 months')
ORDER BY UMA.Reputation DESC, UMA.UserGoldBadges DESC, UMA.UserAcceptedAnswers DESC, CombinedUsers.UserId ASC
LIMIT 1000;