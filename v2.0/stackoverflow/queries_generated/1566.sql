-- {"query": "1566.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3973} 

WITH UserBaseMetrics AS (
    -- Aggregates fundamental user statistics, including self-edits vs. total edits on their posts.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        U.Location,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsOwned,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersOwned,
        SUM(P.Score) AS TotalPostScoreOwned,
        AVG(P.Score) AS AvgPostScoreOwned,
        COUNT(DISTINCT B.Name) AS DistinctBadgeTypes,
        EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate))/86400 AS AccountAgeDays, -- Account age in days
        SUM(COALESCE(P.FavoriteCount, 0)) AS TotalFavoriteCountOnPosts,
        SUM(P.ViewCount) FILTER (WHERE P.PostTypeId = 1) AS TotalViewCountOnQuestions,
        COUNT(DISTINCT PH_SelfEdit.PostId) AS TotalSelfEditedPosts, -- Number of unique posts owned by user, edited by self
        COUNT(DISTINCT PH_AnyEdit.PostId) AS TotalPostsWithAnyEdit -- Number of unique posts owned by user, edited by anyone
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN PostHistory PH_SelfEdit ON P.Id = PH_SelfEdit.PostId AND U.Id = PH_SelfEdit.UserId AND PH_SelfEdit.PostHistoryTypeId IN (4,5,6) -- Post edit types by owner
    LEFT JOIN PostHistory PH_AnyEdit ON P.Id = PH_AnyEdit.PostId AND PH_AnyEdit.PostHistoryTypeId IN (4,5,6) -- Post edit types by any user
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes, U.Location
),
PostDetailedMetrics AS (
    -- Provides detailed metrics for individual posts, including linked/duplicate status and problematic votes.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        COUNT(DISTINCT PH.UserId) AS UniqueEditors,
        MAX(PH.CreationDate) AS LastHistoryActivity,
        AVG(C.Score) AS AvgCommentScore,
        COUNT(DISTINCT PL_Linked.RelatedPostId) AS LinkedPostsCount,
        COUNT(DISTINCT PL_Duplicate.RelatedPostId) AS DuplicateOfCount,
        MAX(CASE WHEN PH_Reopen.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened, -- History type 11 = Post Reopened
        MAX(CASE WHEN PH_Close.PostHistoryTypeId = 10 AND PH_Close.Comment = '101' THEN 1 ELSE 0 END) AS ClosedAsDuplicateByReason, -- Close reason 101 = Duplicate
        EXISTS (SELECT 1 FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 4) AS HasOffensiveVotes -- Correlated subquery: checks for offensive votes on this post
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN PostLinks PL_Linked ON P.Id = PL_Linked.PostId AND PL_Linked.LinkTypeId = 1 -- Linked posts
    LEFT JOIN PostLinks PL_Duplicate ON P.Id = PL_Duplicate.PostId AND PL_Duplicate.LinkTypeId = 3 -- Duplicate posts
    LEFT JOIN PostHistory PH_Reopen ON P.Id = PH_Reopen.PostId AND PH_Reopen.PostHistoryTypeId = 11
    LEFT JOIN PostHistory PH_Close ON P.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount,
        P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.LastEditDate,
        P.LastActivityDate, P.Title, P.Tags
),
UserPostInteractionSummary AS (
    -- Aggregates post-level metrics back to the user, focusing on questions for some calculations.
    SELECT
        UBM.UserId,
        UBM.DisplayName,
        UBM.Reputation,
        UBM.AccountAgeDays,
        UBM.UserProfileViews,
        UBM.UserUpVotes,
        UBM.UserDownVotes,
        UBM.Location,
        UBM.TotalQuestionsOwned,
        UBM.TotalAnswersOwned,
        UBM.AvgPostScoreOwned,
        UBM.DistinctBadgeTypes,
        UBM.TotalFavoriteCountOnPosts,
        UBM.TotalViewCountOnQuestions,
        UBM.TotalSelfEditedPosts,
        UBM.TotalPostsWithAnyEdit,
        SUM(CASE WHEN PDM.PostTypeId = 1 THEN PDM.UniqueEditors ELSE 0 END) AS TotalUniqueEditorsOnQuestions,
        AVG(CASE WHEN PDM.PostTypeId = 1 THEN PDM.AvgCommentScore END) AS AvgCommentScoreOnQuestions,
        SUM(CASE WHEN PDM.PostTypeId = 1 THEN PDM.LinkedPostsCount ELSE 0 END) AS TotalLinkedQuestions,
        SUM(CASE WHEN PDM.PostTypeId = 1 THEN PDM.DuplicateOfCount ELSE 0 END) AS TotalDuplicateQuestions,
        SUM(CASE WHEN PDM.PostTypeId = 1 AND PDM.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestionCount,
        SUM(CASE WHEN PDM.PostTypeId = 1 AND PDM.WasReopened = 1 THEN 1 ELSE 0 END) AS ReopenedQuestionCount,
        SUM(CASE WHEN PDM.PostTypeId = 1 AND PDM.ClosedAsDuplicateByReason = 1 THEN 1 ELSE 0 END) AS ClosedAsDuplicateCount,
        SUM(CASE WHEN PDM.PostTypeId = 1 AND PDM.HasOffensiveVotes THEN 1 ELSE 0 END) AS QuestionsWithOffensiveVotes,
        AVG(EXTRACT(EPOCH FROM (NOW() - PDM.PostCreationDate))/86400) FILTER (WHERE PDM.PostTypeId = 1) AS AvgQuestionAgeDays,
        AVG(EXTRACT(EPOCH FROM (PDM.LastActivityDate - PDM.PostCreationDate))/86400) AS AvgDaysToLastActivity,
        -- Complex string expression to count occurrences of '<sql>' tag within questions
        SUM(LENGTH(PDM.Tags) - LENGTH(REPLACE(PDM.Tags, '><sql><', '')))/LENGTH('sql') FILTER (WHERE PDM.PostTypeId = 1 AND PDM.Tags LIKE '%<sql>%') AS SqlTagUsageCount
    FROM UserBaseMetrics UBM
    LEFT JOIN PostDetailedMetrics PDM ON UBM.UserId = PDM.OwnerUserId
    GROUP BY
        UBM.UserId, UBM.DisplayName, UBM.Reputation, UBM.AccountAgeDays, UBM.UserProfileViews,
        UBM.UserUpVotes, UBM.UserDownVotes, UBM.Location, UBM.TotalQuestionsOwned,
        UBM.TotalAnswersOwned, UBM.AvgPostScoreOwned, UBM.DistinctBadgeTypes,
        UBM.TotalFavoriteCountOnPosts, UBM.TotalViewCountOnQuestions, UBM.TotalSelfEditedPosts,
        UBM.TotalPostsWithAnyEdit
),
RankedUsers AS (
    -- Applies window functions and further calculations to rank and categorize users.
    SELECT
        UPS.UserId,
        UPS.DisplayName,
        UPS.Reputation,
        UPS.AccountAgeDays,
        UPS.UserProfileViews,
        UPS.TotalQuestionsOwned,
        UPS.TotalAnswersOwned,
        UPS.AvgPostScoreOwned,
        UPS.DistinctBadgeTypes,
        UPS.TotalFavoriteCountOnPosts,
        UPS.TotalViewCountOnQuestions,
        UPS.TotalSelfEditedPosts,
        UPS.TotalPostsWithAnyEdit,
        UPS.TotalUniqueEditorsOnQuestions,
        UPS.AvgCommentScoreOnQuestions,
        UPS.TotalLinkedQuestions,
        UPS.TotalDuplicateQuestions,
        UPS.ClosedQuestionCount,
        UPS.ReopenedQuestionCount,
        UPS.ClosedAsDuplicateCount,
        UPS.QuestionsWithOffensiveVotes,
        UPS.AvgQuestionAgeDays,
        UPS.AvgDaysToLastActivity,
        UPS.SqlTagUsageCount,
        RANK() OVER (ORDER BY UPS.Reputation DESC, UPS.TotalQuestionsOwned DESC) AS ReputationRank,
        NTILE(5) OVER (ORDER BY UPS.TotalViewCountOnQuestions DESC) AS TopViewedQuestionsTier, -- Divides users into 5 tiers based on question views
        LAG(UPS.Reputation, 1, 0) OVER (ORDER BY UPS.Reputation DESC) AS PrevReputation, -- Reputation of the user ranked just before current
        COALESCE(CAST(UPS.TotalSelfEditedPosts AS NUMERIC) / NULLIF(UPS.TotalPostsWithAnyEdit, 0), 0) AS SelfEditContributionRatio, -- Proportion of self-edits
        (COALESCE(UPS.AvgCommentScoreOnQuestions, 0) * 10) + (COALESCE(UPS.TotalViewCountOnQuestions, 0) / 1000.0) AS EngagementScore,
        CASE
            WHEN UPS.Reputation >= 10000 AND UPS.TotalQuestionsOwned >= 50 AND UPS.DistinctBadgeTypes >= 15 THEN 'Guru Contributor'
            WHEN UPS.Reputation >= 2000 AND UPS.TotalQuestionsOwned >= 10 AND UPS.DistinctBadgeTypes >= 5 THEN 'Experienced Contributor'
            WHEN UPS.TotalQuestionsOwned > 0 OR UPS.TotalAnswersOwned > 0 THEN 'Active Contributor'
            ELSE 'Passive User'
        END AS UserImpactCategory,
        COALESCE(SUBSTRING(UPS.Location FROM 1 FOR POSITION(',' IN UPS.Location) - 1), UPS.Location, 'Unknown') AS PrimaryLocationArea, -- Extracts primary area from location string
        SUM(CASE WHEN PDM_All.PostTypeId = 1 THEN PDM_All.Score ELSE 0 END) OVER (PARTITION BY UPS.UserId) AS TotalQuestionScore -- Total score of questions owned by the user
    FROM UserPostInteractionSummary UPS
    LEFT JOIN PostDetailedMetrics PDM_All ON UPS.UserId = PDM_All.OwnerUserId -- Another join for complexity, even if partially redundant
    WHERE UPS.TotalQuestionsOwned > 0 OR UPS.TotalAnswersOwned > 0 OR UPS.Reputation > 1 -- Filters out extremely inactive users
    GROUP BY
        UPS.UserId, UPS.DisplayName, UPS.Reputation, UPS.AccountAgeDays, UPS.UserProfileViews,
        UPS.TotalQuestionsOwned, UPS.TotalAnswersOwned, UPS.AvgPostScoreOwned,
        UPS.DistinctBadgeTypes, UPS.TotalFavoriteCountOnPosts, UPS.TotalViewCountOnQuestions,
        UPS.TotalSelfEditedPosts, UPS.TotalPostsWithAnyEdit, UPS.TotalUniqueEditorsOnQuestions,
        UPS.AvgCommentScoreOnQuestions, UPS.TotalLinkedQuestions, UPS.TotalDuplicateQuestions,
        UPS.ClosedQuestionCount, UPS.ReopenedQuestionCount, UPS.ClosedAsDuplicateCount,
        UPS.QuestionsWithOffensiveVotes, UPS.AvgQuestionAgeDays, UPS.AvgDaysToLastActivity,
        UPS.SqlTagUsageCount, UPS.Location
)
-- Main query to find "influential" users
SELECT
    RU.UserId,
    RU.DisplayName,
    RU.Reputation,
    RU.UserImpactCategory,
    RU.ReputationRank,
    RU.TopViewedQuestionsTier,
    RU.TotalQuestionsOwned,
    RU.AvgPostScoreOwned,
    RU.DistinctBadgeTypes,
    RU.SelfEditContributionRatio,
    RU.EngagementScore,
    RU.PrimaryLocationArea,
    -- Weighted influence score combining various metrics
    (RU.Reputation * 0.5 + RU.TotalViewCountOnQuestions * 0.01 + RU.EngagementScore * 0.1 + RU.SelfEditContributionRatio * 100) AS WeightedInfluenceScore,
    -- Scalar subquery: count gold badges received in the last year
    (SELECT COUNT(DISTINCT B.Name) FROM Badges B WHERE B.UserId = RU.UserId AND B.Class = 1 AND B.Date >= NOW() - INTERVAL '1 year') AS GoldBadgesLastYearCount,
    -- NULL logic: display 'N/A' if average comment score is NULL
    COALESCE(CAST(RU.AvgCommentScoreOnQuestions AS VARCHAR), 'N/A') AS FormattedAvgCommentScore,
    -- NULLIF: returns NULL if the count of closed questions is equal to duplicate closed questions
    NULLIF(RU.ClosedQuestionCount, RU.ClosedAsDuplicateCount) AS NonDuplicateClosedQuestions,
    -- Scalar subquery: total deletion votes cast by the user
    (SELECT COUNT(*) FROM PostHistory PH WHERE PH.UserId = RU.UserId AND PH.PostHistoryTypeId = 12) AS TotalDeletionVotesCast
FROM RankedUsers RU
WHERE
    RU.ReputationRank <= 1000 -- Top 1000 users by reputation
    AND RU.TopViewedQuestionsTier = 1 -- Users whose questions are in the top 20% by view count
    AND RU.SelfEditContributionRatio > 0.5 -- Users who significantly contribute to editing their own posts
    AND RU.EngagementScore > 100 -- High overall engagement score
    AND RU.UserImpactCategory IN ('Guru Contributor', 'Experienced Contributor')
    -- Correlated subquery in WHERE clause: Users who own at least one question with a score above the global average question score
    AND EXISTS (
        SELECT 1
        FROM Posts P_sub
        WHERE P_sub.OwnerUserId = RU.UserId
          AND P_sub.PostTypeId = 1
          AND P_sub.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND Score IS NOT NULL)
    )
    -- Complex predicate with date comparisons and string matching
    AND (
        (RU.AccountAgeDays > 365 * 5 AND RU.TotalQuestionsOwned >= 20) -- Users older than 5 years and with at least 20 questions
        OR (RU.Reputation > 5000 AND RU.Location IS NOT NULL AND RU.PrimaryLocationArea LIKE 'New%') -- High rep users from areas starting with 'New'
    )
    AND RU.QuestionsWithOffensiveVotes = 0 -- Filter out users with offensive content on their questions
ORDER BY
    WeightedInfluenceScore DESC, RU.Reputation DESC
LIMIT 500

EXCEPT

-- Exclude "problematic" users from the influential list
SELECT
    RU.UserId,
    RU.DisplayName,
    RU.Reputation,
    RU.UserImpactCategory,
    RU.ReputationRank,
    RU.TopViewedQuestionsTier,
    RU.TotalQuestionsOwned,
    RU.AvgPostScoreOwned,
    RU.DistinctBadgeTypes,
    RU.SelfEditContributionRatio,
    RU.EngagementScore,
    RU.PrimaryLocationArea,
    (RU.Reputation * 0.5 + RU.TotalViewCountOnQuestions * 0.01 + RU.EngagementScore * 0.1 + RU.SelfEditContributionRatio * 100) AS WeightedInfluenceScore,
    (SELECT COUNT(DISTINCT B.Name) FROM Badges B WHERE B.UserId = RU.UserId AND B.Class = 1 AND B.Date >= NOW() - INTERVAL '1 year') AS GoldBadgesLastYearCount,
    COALESCE(CAST(RU.AvgCommentScoreOnQuestions AS VARCHAR), 'N/A') AS FormattedAvgCommentScore,
    NULLIF(RU.ClosedQuestionCount, RU.ClosedAsDuplicateCount) AS NonDuplicateClosedQuestions,
    (SELECT COUNT(*) FROM PostHistory PH WHERE PH.UserId = RU.UserId AND PH.PostHistoryTypeId = 12) AS TotalDeletionVotesCast
FROM RankedUsers RU
WHERE
    RU.ClosedAsDuplicateCount >= 5 -- Users with 5 or more questions closed as duplicate
    OR RU.QuestionsWithOffensiveVotes > 0 -- Users who have questions with offensive votes
    OR (SELECT COUNT(*) FROM PostHistory PH WHERE PH.UserId = RU.UserId AND PH.PostHistoryTypeId = 12) > 10; -- Users who cast more than 10 deletion votes
