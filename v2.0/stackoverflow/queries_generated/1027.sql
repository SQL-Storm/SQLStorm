-- {"query": "1027.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3424} 

WITH UserAggregatedStats AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P_Q.Id) AS TotalQuestionsPosted,
        COUNT(DISTINCT P_A.Id) AS TotalAnswersPosted,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN V_REC.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceivedOnPosts,
        SUM(CASE WHEN V_REC.VoteTypeId = 5 THEN 1 ELSE 0 END) AS TotalFavoritesReceivedOnPosts,
        SUM(CASE WHEN V_GIV.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven,
        SUM(CASE WHEN P_A.Id = P_Q_ACC.AcceptedAnswerId THEN 1 ELSE 0 END) AS TotalAcceptedAnswers,
        MAX(P_Q.CreationDate) AS LastQuestionDate,
        MAX(P_A.CreationDate) AS LastAnswerDate,
        MAX(C.CreationDate) AS LastCommentDate,
        MAX(PH.CreationDate) AS LastHistoryDate
    FROM Users U
    LEFT JOIN Posts P_Q ON U.Id = P_Q.OwnerUserId AND P_Q.PostTypeId = 1
    LEFT JOIN Posts P_A ON U.Id = P_A.OwnerUserId AND P_A.PostTypeId = 2
    LEFT JOIN Posts P_Q_ACC ON P_A.ParentId = P_Q_ACC.Id -- For accepted answers check against parent question
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V_REC ON (P_Q.Id = V_REC.PostId OR P_A.Id = V_REC.PostId) AND V_REC.VoteTypeId IN (2, 5)
    LEFT JOIN Votes V_GIV ON U.Id = V_GIV.UserId AND V_GIV.VoteTypeId IN (3, 4, 10, 12) -- DownMod, Offensive, Deletion, Spam
    LEFT JOIN PostHistory PH ON U.Id = PH.UserId
    GROUP BY U.Id, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostDetailedMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        COALESCE(P.AnswerCount, 0) AS AnswerCount, -- Questions only
        P.CommentCount,
        COALESCE(P.FavoriteCount, 0) AS FavoriteCount,
        P.ClosedDate,
        P.LastActivityDate,
        (SELECT COUNT(DISTINCT C.Id) FROM Comments C WHERE C.PostId = P.Id) AS CurrentCommentCount, -- Correlated subquery
        (SELECT COUNT(DISTINCT PL.Id) FROM PostLinks PL WHERE PL.PostId = P.Id OR PL.RelatedPostId = P.Id) AS TotalLinkReferences,
        COUNT(DISTINCT PH_EDIT.UserId) AS DistinctEditorCount,
        MAX(CASE WHEN PH_STATUS.PostHistoryTypeId IN (10, 35, 12) THEN 1 ELSE 0 END) AS IsClosedOrMigratedOrDeleted, -- Closed (10) or Migrated Away (35) or Deleted (12)
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
        SUM(CASE WHEN V.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotesCount -- For answers
    FROM Posts P
    LEFT JOIN PostHistory PH_EDIT ON P.Id = PH_EDIT.PostId AND PH_EDIT.PostHistoryTypeId IN (4,5,6) -- Edits
    LEFT JOIN PostHistory PH_STATUS ON P.Id = PH_STATUS.PostId AND PH_STATUS.PostHistoryTypeId IN (10, 35, 12) -- Close/Migrate/Delete
    LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (1,2,3)
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.LastActivityDate
),
UserBadgeRanks AS (
    SELECT
        B.UserId,
        B.Name AS BadgeName,
        B.Class AS BadgeClass,
        B.Date AS BadgeDate,
        ROW_NUMBER() OVER (PARTITION BY B.UserId, B.Class ORDER BY B.Date DESC) AS rn_class_date,
        ROW_NUMBER() OVER (PARTITION BY B.UserId ORDER BY B.Date DESC) AS rn_overall_date
    FROM Badges B
),
QuestionTagAnalysis AS (
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName,
        P.Score AS QuestionScore,
        P.ViewCount AS QuestionViewCount
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
QuestionMetricsWithTags AS (
    SELECT
        QTA.QuestionId,
        QTA.OwnerUserId,
        QTA.TagName,
        QTA.QuestionScore,
        QTA.QuestionViewCount,
        T.Count AS TagGlobalCount,
        T.IsModeratorOnly,
        T.IsRequired
    FROM QuestionTagAnalysis QTA
    LEFT JOIN Tags T ON QTA.TagName = T.TagName
),
UserQuestionTagPerformance AS (
    SELECT
        QMT.OwnerUserId AS UserId,
        QMT.TagName,
        COUNT(DISTINCT QMT.QuestionId) AS QuestionsWithTag,
        SUM(QMT.QuestionScore) AS TotalTagScore,
        AVG(QMT.QuestionScore) AS AvgTagScore,
        SUM(QMT.QuestionViewCount) AS TotalTagViewCount,
        RANK() OVER (PARTITION BY QMT.OwnerUserId ORDER BY SUM(QMT.QuestionScore) DESC, COUNT(DISTINCT QMT.QuestionId) DESC) AS UserTagRank
    FROM QuestionMetricsWithTags QMT
    GROUP BY QMT.OwnerUserId, QMT.TagName
),
OverallAverages AS (
    SELECT
        AVG(U.Reputation) AS AvgReputation,
        AVG(UAS.TotalQuestionsPosted) AS AvgQuestions,
        AVG(UAS.TotalAnswersPosted) AS AvgAnswers,
        AVG(PDM.Score) FILTER (WHERE PDM.PostTypeId = 1) AS AvgQuestionScore,
        AVG(PDM.Score) FILTER (WHERE PDM.PostTypeId = 2) AS AvgAnswerScore,
        AVG(EXTRACT(EPOCH FROM (PDM.LastActivityDate - PDM.PostCreationDate))) AS AvgPostLifeSpanSeconds
    FROM Users U
    LEFT JOIN UserAggregatedStats UAS ON U.Id = UAS.UserId
    LEFT JOIN PostDetailedMetrics PDM ON U.Id = PDM.OwnerUserId
)
SELECT
    U.Id AS UserID,
    U.DisplayName,
    U.Reputation,
    U.CreationDate AS UserCreationDate,
    U.LastAccessDate,
    UAS.TotalQuestionsPosted,
    UAS.TotalAnswersPosted,
    UAS.TotalCommentsMade,
    UAS.TotalUpvotesReceivedOnPosts,
    UAS.TotalFavoritesReceivedOnPosts,
    UAS.TotalDownvotesGiven,
    UAS.TotalAcceptedAnswers,
    COALESCE(UAS.LastQuestionDate, UAS.LastAnswerDate, UAS.LastCommentDate, UAS.LastHistoryDate, U.LastAccessDate) AS LastUserActivityDate,
    LEAD(U.Reputation, 1) OVER (ORDER BY U.Reputation DESC) - U.Reputation AS ReputationGapToNextHigher, -- Window function
    NTILE(10) OVER (ORDER BY U.Reputation DESC) AS ReputationDecile, -- Window function
    (SELECT COUNT(DISTINCT B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadgeCount, -- Correlated Subquery
    (SELECT COUNT(DISTINCT B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 2) AS SilverBadgeCount,
    (SELECT COUNT(DISTINCT B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 3) AS BronzeBadgeCount,
    COALESCE(RecentGoldBadge.BadgeName, 'No Gold') AS MostRecentGoldBadge,
    COALESCE(RecentSilverBadge.BadgeName, 'No Silver') AS MostRecentSilverBadge,
    COALESCE(RecentBadgeOverall.BadgeName, 'No Badge') AS MostRecentBadgeOverall,
    AVG(PDM_Q.Score) FILTER (WHERE PDM_Q.PostTypeId = 1) AS AvgQuestionScoreByUser,
    AVG(PDM_A.Score) FILTER (WHERE PDM_A.PostTypeId = 2) AS AvgAnswerScoreByUser,
    SUM(PDM_Q.ViewCount) AS TotalQuestionViewsByUser,
    SUM(PDM_A.AcceptedVotesCount) AS TotalAcceptedAnswersVotesByUser,
    (CAST(UAS.TotalUpvotesReceivedOnPosts AS DECIMAL) / NULLIF(UAS.TotalQuestionsPosted + UAS.TotalAnswersPosted, 0)) AS AvgUpvotesPerPost, -- Complex calculation, NULL handling
    CASE
        WHEN UAS.TotalQuestionsPosted > OA.AvgQuestions AND UAS.TotalAnswersPosted > OA.AvgAnswers THEN 'High Contributor'
        WHEN UAS.TotalQuestionsPosted > OA.AvgQuestions OR UAS.TotalAnswersPosted > OA.AvgAnswers THEN 'Moderate Contributor'
        ELSE 'Low Contributor'
    END AS ContributionLevel, -- Complex expression
    'User-' || LPAD(U.Id::text, 10, '0') || '-' || COALESCE(U.EmailHash, 'NoEmail') AS FormattedUserIDWithHash, -- String expression
    (SELECT PH_LAST.Comment FROM PostHistory PH_LAST WHERE PH_LAST.UserId = U.Id ORDER BY PH_LAST.CreationDate DESC LIMIT 1) AS LastHistoryComment, -- Correlated subquery for recent comment
    COALESCE(OA.AvgReputation, 0) AS GlobalAvgReputation,
    COALESCE(OA.AvgQuestionScore, 0) AS GlobalAvgQuestionScore,
    COALESCE(OA.AvgAnswerScore, 0) AS GlobalAvgAnswerScore,
    COALESCE(MAX(CASE WHEN UQTP.UserTagRank = 1 THEN UQTP.TagName END), 'N/A') AS TopTagByScore, -- String expression with aggregation
    COALESCE(MAX(CASE WHEN UQTP.UserTagRank = 1 THEN UQTP.AvgTagScore END), 0) AS TopTagAvgScore,
    COALESCE(MAX(CASE WHEN UQTP.UserTagRank = 1 THEN UQTP.QuestionsWithTag END), 0) AS TopTagQuestionsCount
FROM Users U
INNER JOIN UserAggregatedStats UAS ON U.Id = UAS.UserId
LEFT JOIN PostDetailedMetrics PDM_Q ON U.Id = PDM_Q.OwnerUserId AND PDM_Q.PostTypeId = 1
LEFT JOIN PostDetailedMetrics PDM_A ON U.Id = PDM_A.OwnerUserId AND PDM_A.PostTypeId = 2
LEFT JOIN UserBadgeRanks RecentGoldBadge ON U.Id = RecentGoldBadge.UserId AND RecentGoldBadge.rn_class_date = 1 AND RecentGoldBadge.BadgeClass = 1
LEFT JOIN UserBadgeRanks RecentSilverBadge ON U.Id = RecentSilverBadge.UserId AND RecentSilverBadge.rn_class_date = 1 AND RecentSilverBadge.BadgeClass = 2
LEFT JOIN UserBadgeRanks RecentBadgeOverall ON U.Id = RecentBadgeOverall.UserId AND RecentBadgeOverall.rn_overall_date = 1
LEFT JOIN UserQuestionTagPerformance UQTP ON U.Id = UQTP.UserId
CROSS JOIN OverallAverages OA -- Cross join for global averages
WHERE U.Reputation > (SELECT AVG(Reputation) FROM Users) -- Non-correlated Subquery in WHERE
AND (U.TotalQuestionsPosted > 0 OR U.TotalAnswersPosted > 0) -- Filter for active users
AND U.Id IN (
    -- Set operator: UNION ALL to find users who either closed a post or had a post migrated
    SELECT DISTINCT UserId FROM PostHistory WHERE PostHistoryTypeId = 10 -- Post Closed
    UNION ALL
    SELECT DISTINCT OwnerUserId FROM Posts P JOIN PostHistory PH ON P.Id = PH.PostId WHERE PH.PostHistoryTypeId = 35 -- Post Migrated Away
)
AND U.LastAccessDate >= (NOW() - INTERVAL '1 year') -- Date calculation
AND EXISTS (
    SELECT 1
    FROM Badges B_EXISTS
    WHERE B_EXISTS.UserId = U.Id
    AND B_EXISTS.Class = 1 -- Has at least one Gold Badge
    AND B_EXISTS.TagBased = TRUE
)
GROUP BY
    U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
    UAS.TotalQuestionsPosted, UAS.TotalAnswersPosted, UAS.TotalCommentsMade,
    UAS.TotalUpvotesReceivedOnPosts, UAS.TotalFavoritesReceivedOnPosts, UAS.TotalDownvotesGiven,
    UAS.TotalAcceptedAnswers, UAS.LastQuestionDate, UAS.LastAnswerDate, UAS.LastCommentDate, UAS.LastHistoryDate,
    RecentGoldBadge.BadgeName, RecentSilverBadge.BadgeName, RecentBadgeOverall.BadgeName,
    OA.AvgReputation, OA.AvgQuestions, OA.AvgAnswers, OA.AvgQuestionScore, OA.AvgAnswerScore, U.EmailHash
HAVING (AVG(PDM_Q.Score) FILTER (WHERE PDM_Q.PostTypeId = 1) > 0 OR AVG(PDM_A.Score) FILTER (WHERE PDM_A.PostTypeId = 2) > 0) -- Having clause based on aggregated scores
   AND SUM(CASE WHEN PDM_Q.IsClosedOrMigratedOrDeleted = 1 THEN 1 ELSE 0 END) + SUM(CASE WHEN PDM_A.IsClosedOrMigratedOrDeleted = 1 THEN 1 ELSE 0 END) < 5 -- Another HAVING condition
ORDER BY U.Reputation DESC, LastUserActivityDate DESC
LIMIT 1000;
