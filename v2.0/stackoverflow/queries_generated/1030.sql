-- {"query": "1030.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3253} 

WITH UserEngagementMetrics AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(U.Views, 0) AS UserProfileViews,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven, -- Votes made by this user
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven, -- Votes made by this user
        COALESCE(SUM(CASE WHEN PV.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesReceivedOnPosts, -- Votes received on user's posts
        COALESCE(SUM(CASE WHEN PV.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesReceivedOnPosts, -- Votes received on user's posts
        CAST(AVG(P.Score) AS NUMERIC(10,2)) AS AvgPostScore,
        NTILE(5) OVER (ORDER BY U.Reputation DESC) AS ReputationQuintile
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Votes AS V ON U.Id = V.UserId -- Votes given by user
    LEFT JOIN Votes AS PV ON P.Id = PV.PostId -- Votes received on user's posts
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views
),
PostHistoryDetails AS (
    SELECT
        PH.PostId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS HistoryDate,
        PH.Comment,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId, PH.PostHistoryTypeId ORDER BY PH.CreationDate DESC) AS rn_latest_per_type_history
    FROM PostHistory AS PH
    WHERE PH.PostHistoryTypeId IN (10, 11, 4, 5, 6) -- Closed, Reopened, Edit Title, Edit Body, Edit Tags
),
PostStatusSummary AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.LastEditDate,
        MAX(CASE WHEN PHD.PostHistoryTypeId = 10 AND PHD.rn_latest_per_type_history = 1 THEN PHD.HistoryDate END) AS LatestClosedDate,
        MAX(CASE WHEN PHD.PostHistoryTypeId = 11 AND PHD.rn_latest_per_type_history = 1 THEN PHD.HistoryDate END) AS LatestReopenedDate,
        (SELECT CR.Name FROM CloseReasonTypes AS CR WHERE CR.Id = CAST(PHD_LatestClose.Comment AS INT) LIMIT 1) AS LatestCloseReason,
        COUNT(DISTINCT CASE WHEN PHD.PostHistoryTypeId IN (4, 5, 6) THEN PHD.HistoryDate END) AS TotalEditEvents,
        MIN(CASE WHEN PHD.PostHistoryTypeId IN (4, 5, 6) THEN PHD.HistoryDate END) AS FirstEditDate,
        MAX(CASE WHEN PHD.PostHistoryTypeId IN (4, 5, 6) THEN PHD.HistoryDate END) AS LastEditByHistoryDate
    FROM Posts AS P
    LEFT JOIN PostHistoryDetails AS PHD ON P.Id = PHD.PostId
    LEFT JOIN PostHistoryDetails AS PHD_LatestClose ON P.Id = PHD_LatestClose.PostId AND PHD_LatestClose.PostHistoryTypeId = 10 AND PHD_LatestClose.rn_latest_per_type_history = 1
    GROUP BY P.Id, P.OwnerUserId, P.PostTypeId, P.CreationDate, P.LastActivityDate, P.LastEditDate
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges
    FROM Badges AS B
    GROUP BY B.UserId
),
UserAcceptedAnswerRatio AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT P.Id) AS TotalAnswersPosted,
        COUNT(DISTINCT PA.Id) AS AcceptedAnswersByThisUser, -- Number of questions where an answer from this user was accepted
        CAST(COUNT(DISTINCT PA.Id) AS NUMERIC) / NULLIF(COUNT(DISTINCT P.Id), 0) AS AcceptedAnswerRatio
    FROM Posts AS P -- This represents the answers
    LEFT JOIN Posts AS Q ON P.ParentId = Q.Id -- The question
    LEFT JOIN Posts AS PA ON Q.AcceptedAnswerId = P.Id AND PA.Id = P.Id -- This user's answer was accepted for its parent question
    WHERE P.PostTypeId = 2 -- Only consider answers
    GROUP BY P.OwnerUserId
)
SELECT
    UEM.UserId,
    UEM.DisplayName,
    UEM.Reputation,
    UEM.ReputationQuintile,
    UEM.UserProfileViews,
    UEM.TotalQuestions,
    UEM.TotalAnswers,
    UEM.TotalCommentsMade,
    UEM.TotalUpvotesGiven,
    UEM.TotalDownvotesGiven,
    UEM.TotalUpvotesReceivedOnPosts,
    UEM.TotalDownvotesReceivedOnPosts,
    COALESCE(UEM.AvgPostScore, 0) AS AvgPostScore,
    UBS.GoldBadges,
    UBS.SilverBadges,
    UBS.BronzeBadges,
    UBS.TotalBadges,
    UBS.TagBasedBadges,
    UAAR.TotalAnswersPosted,
    UAAR.AcceptedAnswersByThisUser,
    COALESCE(UAAR.AcceptedAnswerRatio, 0.0) AS AcceptedAnswerRatio,
    PSR_Agg.LatestPostActivity,
    PSR_Agg.LatestPostEdit,
    PSR_Agg.ClosedQuestionCount,
    PSR_Agg.ReopenedQuestionCount,
    PSR_Agg.DuplicateClosedQuestionCount,
    PSR_Agg.OffTopicClosedQuestionCount,
    -- Window functions
    RANK() OVER (ORDER BY UEM.Reputation DESC, UEM.TotalUpvotesReceivedOnPosts DESC) AS UserOverallRank,
    DENSE_RANK() OVER (PARTITION BY UEM.ReputationQuintile ORDER BY UEM.TotalAnswers DESC, UEM.AcceptedAnswerRatio DESC) AS AnswerRankInQuintile,
    LAG(UEM.Reputation, 1, 0) OVER (ORDER BY UEM.Reputation ASC) AS ReputationOfPreviousUser,
    LEAD(UEM.Reputation, 1, 0) OVER (ORDER BY UEM.Reputation ASC) AS ReputationOfNextUser,
    -- Correlated Subqueries & Complex Expressions
    (SELECT COUNT(DISTINCT PH.PostId)
     FROM PostHistory AS PH
     WHERE PH.UserId = UEM.UserId
       AND PH.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
       AND PH.CreationDate > UEM.UserCreationDate + INTERVAL '3 months' -- Edits after initial 3 months
    ) AS PostEditsAfterEarlyPhase,
    CASE
        WHEN UEM.TotalQuestions > 0 AND UEM.TotalAnswers > 0 AND UEM.TotalCommentsMade > 10 THEN 'Pro-Active Contributor'
        WHEN UEM.TotalQuestions > 0 AND UEM.TotalAnswers = 0 THEN 'Primary Questioner'
        WHEN UEM.TotalAnswers > 0 AND UEM.TotalQuestions = 0 THEN 'Dedicated Answerer'
        WHEN UEM.TotalCommentsMade > 20 THEN 'Social Commentator'
        ELSE 'Casual User'
    END AS UserEngagementCategory,
    -- String expressions and NULL logic
    (
        SELECT STRING_AGG(DISTINCT T.TagName, '; ')
        FROM Posts AS P_Tags
        CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(P_Tags.Tags, 2, LENGTH(P_Tags.Tags) - 2), '><')) AS T(TagName)
        WHERE P_Tags.OwnerUserId = UEM.UserId AND P_Tags.PostTypeId = 1 -- Only questions for tag summary
        GROUP BY P_Tags.OwnerUserId
    ) AS TopQuestionTags,
    NULLIF(UEM.TotalQuestions + UEM.TotalAnswers + UEM.TotalCommentsMade + UEM.TotalUpvotesGiven + UEM.TotalDownvotesGiven, 0) AS TotalUserInteractions,
    -- More calculations
    EXTRACT(EPOCH FROM (UEM.LastAccessDate - UEM.UserCreationDate)) / (60 * 60 * 24 * 30.4375) AS MonthsOnPlatform, -- Average months
    CAST(UEM.TotalUpvotesReceivedOnPosts AS NUMERIC) / NULLIF(UEM.TotalDownvotesReceivedOnPosts, 0) AS PostUpvoteDownvoteRatio,
    COALESCE(PSR_Agg.HasLinkedOrDuplicatePost, FALSE) AS HasRelatedPost, -- NULL logic
    PSR_Agg.LatestCloseReason AS LastQuestionCloseReason,
    -- Average statistics for the user's reputation quintile (correlated subqueries for aggregation)
    (SELECT CAST(AVG(uem_inner.TotalUpvotesReceivedOnPosts) AS NUMERIC(10,2))
     FROM UserEngagementMetrics uem_inner
     WHERE uem_inner.ReputationQuintile = UEM.ReputationQuintile) AS AvgUpvotesInQuintile,
    (SELECT CAST(AVG(uem_inner.TotalAnswers) AS NUMERIC(10,2))
     FROM UserEngagementMetrics uem_inner
     WHERE uem_inner.ReputationQuintile = UEM.ReputationQuintile) AS AvgAnswersInQuintile
FROM UserEngagementMetrics AS UEM
LEFT JOIN UserBadgeSummary AS UBS ON UEM.UserId = UBS.UserId
LEFT JOIN UserAcceptedAnswerRatio AS UAAR ON UEM.UserId = UAAR.UserId
LEFT JOIN ( -- Aggregate post status and link information per user
    SELECT
        PSS.OwnerUserId,
        MAX(PSS.LastActivityDate) AS LatestPostActivity,
        MAX(PSS.LastEditDate) AS LatestPostEdit,
        COUNT(DISTINCT CASE WHEN PSS.LatestClosedDate IS NOT NULL AND PSS.PostTypeId = 1 THEN PSS.PostId END) AS ClosedQuestionCount,
        COUNT(DISTINCT CASE WHEN PSS.LatestReopenedDate IS NOT NULL AND PSS.PostTypeId = 1 THEN PSS.PostId END) AS ReopenedQuestionCount,
        COUNT(DISTINCT CASE WHEN PSS.LatestCloseReason = 'Duplicate' AND PSS.PostTypeId = 1 THEN PSS.PostId END) AS DuplicateClosedQuestionCount,
        COUNT(DISTINCT CASE WHEN PSS.LatestCloseReason LIKE '%Off-topic%' AND PSS.PostTypeId = 1 THEN PSS.PostId END) AS OffTopicClosedQuestionCount,
        BOOL_OR(PL.LinkTypeId IS NOT NULL) AS HasLinkedOrDuplicatePost, -- Boolean aggregation for existence
        MAX(PSS.LatestCloseReason) FILTER (WHERE PSS.PostTypeId = 1) AS LatestCloseReason
    FROM PostStatusSummary AS PSS
    LEFT JOIN PostLinks AS PL ON PSS.PostId = PL.PostId -- Check for linked/duplicate posts
    GROUP BY PSS.OwnerUserId
) AS PSR_Agg ON UEM.UserId = PSR_Agg.OwnerUserId
WHERE
    UEM.Reputation >= 500 -- Minimum reputation threshold
    AND UEM.UserCreationDate < NOW() - INTERVAL '1 year' -- User must be active for at least 1 year
    AND (
        (UEM.TotalQuestions > 5 OR UEM.TotalAnswers > 10 OR UEM.TotalCommentsMade > 50) -- Active in content creation/commenting
        AND (UEM.TotalUpvotesReceivedOnPosts > 50 AND UEM.TotalDownvotesReceivedOnPosts < 20) -- Generally well-received posts
    )
    AND (
        (UBS.GoldBadges > 0 OR UBS.SilverBadges > 2) -- Has significant badges
        OR (UAAR.AcceptedAnswerRatio > 0.4 AND UAAR.TotalAnswersPosted > 5) -- Or is good at getting answers accepted
        OR (UEM.ReputationQuintile = 1 AND UEM.UserProfileViews > 1000) -- Or is a top-tier user with high profile views
    )
    AND NOT EXISTS ( -- Correlated subquery for exclusion (mimics EXCEPT logic conceptually)
        SELECT 1
        FROM PostStatusSummary AS PSS_EXC
        WHERE PSS_EXC.OwnerUserId = UEM.UserId
          AND PSS_EXC.PostTypeId = 1 -- Only questions
          AND PSS_EXC.LatestClosedDate IS NOT NULL
          AND EXTRACT(EPOCH FROM (NOW() - PSS_EXC.LatestClosedDate)) / (60 * 60 * 24 * 7) < 4 -- Closed within last 4 weeks
        HAVING COUNT(DISTINCT PSS_EXC.PostId) > 2 -- More than 2 questions closed recently
    )
ORDER BY
    UserOverallRank ASC,
    UEM.Reputation DESC,
    UEM.DisplayName ASC
LIMIT 5000;
