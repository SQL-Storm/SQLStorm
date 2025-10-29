-- {"query": "1091.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4439} 

WITH UserEngagement AS (
    -- Aggregates basic user activity counts from Posts and Comments, incorporating NULL logic for sums
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT Q.Id) AS TotalQuestionsPosted,
        COUNT(DISTINCT A.Id) AS TotalAnswersPosted,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(COALESCE(Q.ViewCount, 0)) AS TotalQuestionViews,
        SUM(COALESCE(Q.FavoriteCount, 0)) AS TotalQuestionFavorites,
        SUM(COALESCE(Q.Score, 0)) AS TotalQuestionScore,
        SUM(COALESCE(A.Score, 0)) AS TotalAnswerScore,
        SUM(CASE WHEN A.AcceptedAnswerId IS NOT NULL AND A.PostTypeId = 2 AND A.OwnerUserId = U.Id THEN 1 ELSE 0 END) AS AcceptedAnswersProvidedCount,
        SUM(CASE WHEN Q.AcceptedAnswerId IS NOT NULL AND Q.PostTypeId = 1 AND Q.OwnerUserId = U.Id THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswerCount
    FROM Users U
    LEFT JOIN Posts Q ON U.Id = Q.OwnerUserId AND Q.PostTypeId = 1
    LEFT JOIN Posts A ON U.Id = A.OwnerUserId AND A.PostTypeId = 2
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
QuestionDetails AS (
    -- Extracts detailed information for questions, including a correlated subquery and a window function
    SELECT
        P.OwnerUserId AS UserId,
        P.Id AS PostId,
        P.Title,
        P.CreationDate AS QuestionCreationDate,
        P.Score AS QuestionScore,
        P.ViewCount AS QuestionViewCount,
        P.FavoriteCount AS QuestionFavoriteCount,
        P.Tags,
        -- Correlated subquery: Count distinct related (linked) posts of type 1
        (SELECT COUNT(DISTINCT PL.RelatedPostId)
         FROM PostLinks PL
         WHERE PL.PostId = P.Id
           AND PL.LinkTypeId = 1) AS LinkedPostCount,
        -- Window function: Rank user's questions by score for identifying top questions
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC) AS RankByScoreWithinUserQuestions
    FROM Posts P
    WHERE P.PostTypeId = 1
      AND P.CreationDate >= (CURRENT_DATE - INTERVAL '10 year') -- Limit data for performance
),
AnswerDetails AS (
    -- Extracts detailed information for answers, including a correlated subquery and a window function
    SELECT
        A.OwnerUserId AS UserId,
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.Score AS AnswerScore,
        A.CreationDate AS AnswerCreationDate,
        A.LastEditDate,
        A.AcceptedAnswerId IS NOT NULL AS IsAcceptedAnswerActual, -- Checks if this answer *was* accepted for its parent question
        -- Correlated subquery: Get count of unique users commenting on this specific answer
        (SELECT COUNT(DISTINCT CM.UserId) FROM Comments CM WHERE CM.PostId = A.Id AND CM.UserId IS NOT NULL) AS UniqueCommentersOnAnswer,
        -- Window function: Rank answers within their parent question by score
        DENSE_RANK() OVER (PARTITION BY A.ParentId ORDER BY A.Score DESC, A.CreationDate ASC) AS RankInParentQuestion
    FROM Posts A
    WHERE A.PostTypeId = 2
      AND A.CreationDate >= (CURRENT_DATE - INTERVAL '10 year') -- Limit data for performance
),
PostHistoryAnalysis AS (
    -- Analyzes post history for various events, using CASE WHEN for classification and string parsing
    SELECT
        PH.UserId,
        PH.PostId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS HistoryDate,
        PH.Comment,
        PH.Text,
        -- Complicated Predicate/Expression: Classify history event type with NULL logic in condition
        CASE
            WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) AND PH.Comment IS NOT NULL THEN 'EditRollbackCommented'
            WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 'EditRollbackUncommented'
            WHEN PH.PostHistoryTypeId IN (10, 11) THEN 'CloseReopen'
            WHEN PH.PostHistoryTypeId IN (12, 13) THEN 'DeleteUndelete'
            WHEN PH.PostHistoryTypeId IN (19, 20) THEN 'ProtectUnprotect'
            WHEN PH.PostHistoryTypeId IN (35, 36) THEN 'Migrate'
            ELSE 'OtherHistory'
        END AS HistoryEventType,
        -- String expression and NULL logic: Extract numeric value from Comment field if it looks like an ID
        COALESCE(
            NULLIF(SUBSTRING(PH.Comment FROM '[0-9]+'), ''),
            '0'
        ) AS ExtractedNumericCommentId
    FROM PostHistory PH
    WHERE PH.UserId IS NOT NULL -- Focus on actions by registered users
      AND PH.CreationDate >= (CURRENT_DATE - INTERVAL '5 year') -- Limit history range for performance
),
AggregatedHistory AS (
    -- Aggregates history events per user from PostHistoryAnalysis
    SELECT
        UserId,
        COUNT(CASE WHEN HistoryEventType = 'EditRollbackCommented' THEN 1 END) AS TotalEditRollbackCommentedEvents,
        COUNT(CASE WHEN HistoryEventType = 'EditRollbackUncommented' THEN 1 END) AS TotalEditRollbackUncommentedEvents,
        COUNT(CASE WHEN HistoryEventType = 'CloseReopen' THEN 1 END) AS TotalCloseReopenEvents,
        COUNT(CASE WHEN HistoryEventType = 'DeleteUndelete' THEN 1 END) AS TotalDeleteUndeleteEvents,
        COUNT(DISTINCT PostId) AS UniquePostsWithHistoryEvents,
        MAX(HistoryDate) AS LastRecordedHistoryEventDate
    FROM PostHistoryAnalysis
    GROUP BY UserId
),
BadgeSummary AS (
    -- Summarizes badge acquisition per user, including a window function and complex filtering
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        -- Window function: Categorize users into quartiles based on Gold Badges count
        NTILE(4) OVER (ORDER BY SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) DESC, COUNT(B.Id) DESC) AS GoldBadgeQuartile
    FROM Badges B
    WHERE B.Date >= (CURRENT_DATE - INTERVAL '7 year') -- Filter for more recent badge activity
    GROUP BY B.UserId
    HAVING COUNT(B.Id) > 5 -- Only consider users with a reasonable number of badges
),
AvgUserQuestionStats AS (
    -- Averages and counts for user questions, including string expression for tag filtering
    SELECT
        QE.UserId,
        AVG(QE.QuestionScore) AS AvgQuestionScore,
        AVG(QE.QuestionViewCount) AS AvgQuestionViewCount,
        SUM(CASE WHEN QE.Tags LIKE '%<sql>%' OR QE.Tags LIKE '%<postgresql>%' OR QE.Tags LIKE '%<mysql>%' OR QE.Tags LIKE '%<database>%' THEN 1 ELSE 0 END) AS DatabaseRelatedQuestions,
        COUNT(DISTINCT QE.PostId) AS QuestionsPosted,
        SUM(CASE WHEN QE.RankByScoreWithinUserQuestions = 1 THEN 1 ELSE 0 END) AS TopScoringUserQuestions
    FROM QuestionDetails QE
    GROUP BY QE.UserId
),
AvgUserAnswerStats AS (
    -- Averages and counts for user answers
    SELECT
        AD.UserId,
        AVG(AD.AnswerScore) AS AvgAnswerScore,
        SUM(CASE WHEN AD.IsAcceptedAnswerActual THEN 1 ELSE 0 END) AS AnswersAcceptedByOthers,
        SUM(AD.UniqueCommentersOnAnswer) AS TotalUniqueCommentersOnAnswers,
        COUNT(DISTINCT AD.AnswerId) AS AnswersPosted,
        SUM(CASE WHEN AD.RankInParentQuestion = 1 THEN 1 ELSE 0 END) AS TopScoringAnswersInQuestions
    FROM AnswerDetails AD
    GROUP BY AD.UserId
),
UserProfilingBase AS (
    -- Combines all summary CTEs using LEFT JOINs, and calculates a complex engagement index
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.CreationDate,
        UE.LastAccessDate,
        UE.TotalQuestionsPosted,
        UE.TotalAnswersPosted,
        UE.TotalCommentsMade,
        UE.TotalQuestionViews,
        UE.TotalQuestionFavorites,
        UE.TotalQuestionScore,
        UE.TotalAnswerScore,
        UE.AcceptedAnswersProvidedCount,
        UE.QuestionsWithAcceptedAnswerCount,
        AUQS.AvgQuestionScore,
        AUQS.AvgQuestionViewCount,
        AUQS.DatabaseRelatedQuestions,
        AUQS.QuestionsPosted,
        AUQS.TopScoringUserQuestions,
        AUAS.AvgAnswerScore,
        AUAS.AnswersAcceptedByOthers,
        AUAS.TotalUniqueCommentersOnAnswers,
        AUAS.AnswersPosted,
        AUAS.TopScoringAnswersInQuestions,
        AHA.TotalEditRollbackCommentedEvents,
        AHA.TotalEditRollbackUncommentedEvents,
        AHA.TotalCloseReopenEvents,
        AHA.TotalDeleteUndeleteEvents,
        AHA.UniquePostsWithHistoryEvents,
        AHA.LastRecordedHistoryEventDate,
        BS.TotalBadges,
        BS.GoldBadges,
        BS.SilverBadges,
        BS.BronzeBadges,
        BS.GoldBadgeQuartile,
        -- Complicated calculation for 'UserEngagementIndex' with COALESCE and weighting, handling potential NULLs
        (
            (COALESCE(UE.TotalQuestionScore, 0) * 0.10) +
            (COALESCE(UE.TotalAnswerScore, 0) * 0.15) +
            (COALESCE(UE.TotalQuestionViews, 0) * 0.02) +
            (COALESCE(UE.TotalQuestionFavorites, 0) * 0.08) +
            (COALESCE(UE.AcceptedAnswersProvidedCount, 0) * 0.20) +
            (COALESCE(AUQS.TopScoringUserQuestions, 0) * 0.10) +
            (COALESCE(AUAS.TopScoringAnswersInQuestions, 0) * 0.10) +
            (COALESCE(AHA.TotalEditRollbackCommentedEvents, 0) * 0.05) +
            (COALESCE(BS.GoldBadges, 0) * 0.20)
        ) AS UserEngagementIndex
    FROM UserEngagement UE
    LEFT JOIN AvgUserQuestionStats AUQS ON UE.UserId = AUQS.UserId
    LEFT JOIN AvgUserAnswerStats AUAS ON UE.UserId = AUAS.UserId
    LEFT JOIN AggregatedHistory AHA ON UE.UserId = AHA.UserId
    LEFT JOIN BadgeSummary BS ON UE.UserId = BS.UserId
),
SpecificTechContributors AS (
    -- Uses UNION ALL to combine different sets of users contributing to specific tech tags, with complicated predicates
    SELECT
        DISTINCT U.Id AS UserId,
        U.DisplayName,
        'SQL_Tech_Contributor' AS ContributionCategory,
        COUNT(P.Id) AS TaggedPostsCount
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE P.PostTypeId = 1
      AND P.Tags LIKE '%<sql>%'
      AND P.CreationDate BETWEEN '2021-01-01' AND '2023-12-31'
    GROUP BY U.Id, U.DisplayName
    HAVING COUNT(P.Id) > 3 AND SUM(P.Score) > 10 -- Minimum posts and score for qualification
    UNION ALL
    SELECT
        DISTINCT U.Id AS UserId,
        U.DisplayName,
        'Python_ML_Contributor' AS ContributionCategory,
        COUNT(P.Id) AS TaggedPostsCount
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE P.PostTypeId = 1
      AND (P.Tags LIKE '%<python>%' OR P.Tags LIKE '%<machine-learning>%')
      AND P.CreationDate BETWEEN '2021-01-01' AND '2023-12-31'
    GROUP BY U.Id, U.DisplayName
    HAVING COUNT(P.Id) > 5 AND SUM(P.Score) > 15 -- Minimum posts and score for qualification
),
AdvancedUserMetrics AS (
    -- Adds more complex window functions (LAG, LEAD) and conditional logic for user classification
    SELECT
        UPB.*,
        -- Window function: Get engagement index of the previous user (by reputation and engagement)
        LAG(UPB.UserEngagementIndex, 1, 0.0) OVER (ORDER BY UPB.Reputation DESC, UPB.UserEngagementIndex DESC) AS PreviousEngagementIndex,
        -- Window function: Get reputation of the next user (by reputation and engagement)
        LEAD(UPB.Reputation, 1, 9999999) OVER (ORDER BY UPB.Reputation DESC, UPB.UserEngagementIndex DESC) AS NextUserReputation,
        -- Complicated predicate/expression for detailed user role classification
        CASE
            WHEN UPB.GoldBadges >= 5 AND UPB.TotalQuestionsPosted >= 10 AND COALESCE(UPB.AvgQuestionScore, 0) >= 20 THEN 'Question Guru'
            WHEN UPB.AnswersAcceptedByOthers >= 50 AND COALESCE(UPB.TotalAnswerScore, 0) >= 500 AND UPB.TopScoringAnswersInQuestions >= 10 THEN 'Answer Luminary'
            WHEN UPB.TotalEditRollbackCommentedEvents >= 100 AND UPB.UniquePostsWithHistoryEvents >= 50 THEN 'Community Editor'
            ELSE 'General Contributor'
        END AS DetailedUserRole,
        -- Conditional calculation: Reputation per year active, handling division by zero with GREATEST
        UPB.Reputation / GREATEST(1, EXTRACT(YEAR FROM CURRENT_DATE) - EXTRACT(YEAR FROM UPB.CreationDate)) AS ReputationPerYearActive
    FROM UserProfilingBase UPB
    WHERE UPB.Reputation > 5000 -- Filter for more established users
      AND UPB.CreationDate <= (CURRENT_DATE - INTERVAL '2 year') -- Only users active for at least 2 years
)
-- Final SELECT statement, combining all CTEs with a LEFT JOIN and applying final filters, string operations, and correlated subqueries
SELECT
    AUM.UserId,
    AUM.DisplayName,
    AUM.Reputation,
    AUM.UserEngagementIndex,
    AUM.DetailedUserRole,
    AUM.TotalQuestionsPosted,
    AUM.TotalAnswersPosted,
    AUM.GoldBadges,
    AUM.AvgQuestionScore,
    AUM.AvgAnswerScore,
    AUM.TotalEditRollbackCommentedEvents,
    AUM.LastRecordedHistoryEventDate,
    AUM.ReputationPerYearActive,
    STC.ContributionCategory,
    STC.TaggedPostsCount,
    -- Complicated expression: Ratio of total badges to total posts, with NULLIF for division by zero
    CAST(AUM.TotalBadges AS NUMERIC) / NULLIF((AUM.TotalQuestionsPosted + AUM.TotalAnswersPosted), 0) AS BadgeToPostRatio,
    -- String expression: Generate a 'User Code' from parts of display name and user ID, with NULL handling
    UPPER(LEFT(COALESCE(AUM.DisplayName, 'UNKNOWN'), 3)) || '-' || LPAD(CAST(AUM.UserId AS TEXT), 6, '0') || '-' || LOWER(REPLACE(COALESCE(STC.ContributionCategory, 'None'), '_', '')) AS UserCode,
    -- NULL logic and complex boolean comparison using LAG/LEAD results
    (AUM.UserEngagementIndex > COALESCE(AUM.PreviousEngagementIndex, 0)) AND (AUM.Reputation < COALESCE(AUM.NextUserReputation, 9999999)) AS IsImprovingButNotTopAdjacent,
    -- Correlated subquery in SELECT: Check for recent accepted answers *given* by this user
    (SELECT COUNT(P.Id)
     FROM Posts P
     WHERE P.OwnerUserId = AUM.UserId
       AND P.PostTypeId = 2
       AND P.AcceptedAnswerId IS NOT NULL -- This post was accepted by its parent question's owner
       AND P.CreationDate >= (CURRENT_DATE - INTERVAL '90 days')) AS RecentAcceptedAnswersGiven,
    -- Correlated subquery in WHERE clause for exclusion (NOT EXISTS), also demonstrating NULL logic
    NOT EXISTS (
        SELECT 1
        FROM Badges B
        WHERE B.UserId = AUM.UserId
          AND B.Name ILIKE '%suffering%' -- Example badge name for negative correlation
          AND B.Date >= (AUM.LastAccessDate - INTERVAL '1 year')
          AND AUM.LastAccessDate IS NOT NULL -- Ensures LastAccessDate is considered for the interval
    ) AS NotRecentlySuffering
FROM AdvancedUserMetrics AUM
LEFT JOIN SpecificTechContributors STC ON AUM.UserId = STC.UserId
WHERE AUM.Reputation > 2000
  AND AUM.UserEngagementIndex > 100
  AND (AUM.DisplayName IS NOT NULL AND LENGTH(TRIM(AUM.DisplayName)) > 2)
  AND (AUM.LastAccessDate IS NOT NULL AND AUM.LastAccessDate >= (CURRENT_DATE - INTERVAL '6 month')) -- Active recently
  AND (STC.ContributionCategory IS NOT NULL OR AUM.DatabaseRelatedQuestions > 0) -- Either a specific tech contributor or has relevant questions
  AND (AUM.DetailedUserRole = 'Question Guru' OR AUM.DetailedUserRole = 'Answer Luminary' OR AUM.DetailedUserRole = 'Community Editor') -- Complex role filter
  -- More complex NULL handling and numeric comparison with averaged scores
  AND (COALESCE(AUM.AvgQuestionScore, 0) + COALESCE(AUM.AvgAnswerScore, 0)) / 2.0 > 15
ORDER BY AUM.UserEngagementIndex DESC, AUM.Reputation DESC, AUM.DetailedUserRole
LIMIT 1000;
