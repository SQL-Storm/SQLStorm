-- {"query": "1720.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3053} 

WITH UserActivitySummary AS (
    -- Gathers comprehensive activity metrics for each user, including post counts, scores, and badge distribution.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserTotalUpVotes,
        U.DownVotes AS UserTotalDownVotes,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        COALESCE(LENGTH(U.AboutMe), 0) AS AboutMeLength,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COALESCE(SUM(P.Score), 0) AS TotalPostsScore,
        COALESCE(SUM(P.ViewCount), 0) AS TotalPostsViewCount,
        COALESCE(SUM(P.FavoriteCount), 0) AS TotalPostsFavoriteCount,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentsScoreGiven,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE NULL END) AS AverageAnswerScore,
        COUNT(B.Id) FILTER (WHERE B.Class = 1) AS GoldBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 2) AS SilverBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 3) AS BronzeBadges
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes,
        U.CreationDate, U.LastAccessDate, U.AboutMe
),
QuestionDetailedPerformance AS (
    -- Analyzes specific performance indicators and historical data for questions.
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.AnswerCount AS QuestionAnswerCount,
        Q.FavoriteCount AS QuestionFavoriteCount,
        Q.ClosedDate AS QuestionClosedDate,
        Q.CommunityOwnedDate AS QuestionCommunityOwnedDate,
        -- Extract the primary tag (first tag)
        NULLIF(SUBSTRING(Q.Tags, 2, POSITION('><' IN Q.Tags) - 2), '') AS PrimaryTag,
        -- Count various history event types
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditHistoryCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 12) THEN 1 ELSE 0 END) AS CloseDeleteHistoryCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS LastReopenedDate,
        -- Determine if a question was closed for being a duplicate based on PostHistory.Comment
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 AND PH.Comment = '101' THEN 1 ELSE 0 END) AS IsClosedAsDuplicate,
        -- Correlated subquery to find the score of the accepted answer (if any)
        (
            SELECT COALESCE(MAX(A.Score), 0)
            FROM Posts AS A
            WHERE A.Id = Q.AcceptedAnswerId AND A.PostTypeId = 2
        ) AS AcceptedAnswerScore,
        -- Correlated subquery to count highly-viewed related posts (LinkType = 1 for 'Linked')
        (
            SELECT COUNT(PL_Inner.RelatedPostId)
            FROM PostLinks AS PL_Inner
            JOIN Posts AS P_Inner ON PL_Inner.RelatedPostId = P_Inner.Id
            WHERE PL_Inner.PostId = Q.Id AND PL_Inner.LinkTypeId = 1 AND P_Inner.ViewCount > 50000
        ) AS HighViewLinkedPostCount,
        -- Calculate the age of the question in days
        EXTRACT(EPOCH FROM (NOW() - Q.CreationDate)) / 86400 AS QuestionAgeDays
    FROM Posts AS Q
    LEFT JOIN PostHistory AS PH ON Q.Id = PH.PostId
    WHERE Q.PostTypeId = 1 AND Q.OwnerUserId IS NOT NULL -- Focus on questions with known owners
    GROUP BY
        Q.Id, Q.OwnerUserId, Q.CreationDate, Q.Score, Q.ViewCount, Q.AnswerCount,
        Q.FavoriteCount, Q.ClosedDate, Q.CommunityOwnedDate, Q.Tags, Q.AcceptedAnswerId
),
AnswerEngagementMetrics AS (
    -- Aggregates metrics for answers associated with each question, including comment scores.
    SELECT
        P.ParentId AS QuestionId,
        COUNT(P.Id) AS TotalAnswersOnQuestion,
        SUM(P.Score) AS TotalAnswerScoreOnQuestion,
        AVG(P.Score) AS AvgAnswerScoreOnQuestion,
        MAX(P.CreationDate) AS LatestAnswerDateOnQuestion,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentsScoreForAnswers,
        MAX(P.Score) FILTER (WHERE P.PostTypeId = 2) AS MaxAnswerScoreOnQuestion
    FROM Posts AS P
    LEFT JOIN Comments AS C ON P.Id = C.PostId
    WHERE P.PostTypeId = 2 AND P.ParentId IS NOT NULL
    GROUP BY P.ParentId
),
PopularTagAnalysis AS (
    -- Identifies and ranks tags by their popularity based on associated questions' views and scores.
    SELECT
        TagName,
        COUNT(T.Id) AS TaggedPostCount,
        SUM(P.ViewCount) AS TotalViewsForTag,
        AVG(P.Score) AS AvgScoreForTag,
        NTILE(5) OVER (ORDER BY SUM(P.ViewCount) DESC, AVG(P.Score) DESC) AS TagPopularityQuintile
    FROM Posts AS P,
         UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')) AS TagName
    JOIN Tags AS T ON TagName = T.TagName
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    GROUP BY TagName
    HAVING COUNT(T.Id) > 100 -- Filter for tags with significant usage
),
ModeratorInterventionSummary AS (
    -- Summarizes moderator actions on posts, providing a history count and last action date.
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalInterventionEvents,
        MAX(PH.CreationDate) AS LastModeratorActionDate,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 12, 14, 19) THEN 1 ELSE 0 END) AS CriticalModeratorActions, -- Closed, Deleted, Locked, Protected
        RANK() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS LatestHistoryEventRank
    FROM PostHistory AS PH
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 33, 34) -- Various mod-related actions
    GROUP BY PH.PostId
    HAVING SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 12, 14, 19) THEN 1 ELSE 0 END) > 0
)
-- Main query: Combines all derived data to analyze user and question performance,
-- applying complex logic, window functions, and NULL handling for a comprehensive view.
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.UserProfileViews,
    UAS.TotalPostsCreated,
    UAS.QuestionsAsked,
    UAS.AnswersProvided,
    UAS.TotalPostsScore,
    UAS.TotalPostsViewCount,
    UAS.GoldBadges,
    UAS.SilverBadges,
    UAS.BronzeBadges,
    QDP.QuestionId,
    QDP.QuestionCreationDate,
    QDP.QuestionScore,
    QDP.QuestionViewCount,
    QDP.QuestionAnswerCount,
    QDP.PrimaryTag,
    QDP.AcceptedAnswerScore,
    QDP.EditHistoryCount,
    QDP.IsClosedAsDuplicate,
    QDP.HighViewLinkedPostCount,
    QDP.QuestionAgeDays,
    COALESCE(AEM.TotalAnswersOnQuestion, 0) AS CurrentAnswersOnQuestion,
    COALESCE(AEM.AvgAnswerScoreOnQuestion, 0.0) AS AverageAnswerScoreForQuestion,
    COALESCE(AEM.LatestAnswerDateOnQuestion, QDP.QuestionCreationDate) AS LastAnswerActivity,
    COALESCE(PMA.CriticalModeratorActions, 0) AS CriticalModActionsOnQuestion,
    PMA.LastModeratorActionDate,
    PTA.TagPopularityQuintile,
    -- Custom composite score for overall question quality and user impact
    ROUND(
        (QDP.QuestionScore * 0.4) +
        (QDP.QuestionViewCount / 1000.0 * 0.2) +
        (COALESCE(AEM.AvgAnswerScoreOnQuestion, 0.0) * 0.2) +
        (QDP.AcceptedAnswerScore * 0.1) +
        (CASE WHEN QDP.QuestionClosedDate IS NULL THEN 10 ELSE -5 END) + -- Bonus for open questions
        (CASE WHEN QDP.IsClosedAsDuplicate = 1 THEN -20 ELSE 0 END) + -- Penalty for duplicate closure
        (UAS.Reputation / 100.0 * 0.1), -- User reputation impact
        2
    ) AS QuestionImpactScore,
    -- Categorize questions based on their state and engagement
    CASE
        WHEN QDP.QuestionClosedDate IS NOT NULL AND QDP.LastReopenedDate IS NULL THEN 'Closed_Permanent'
        WHEN QDP.QuestionClosedDate IS NOT NULL AND QDP.LastReopenedDate IS NOT NULL AND QDP.LastReopenedDate > QDP.QuestionClosedDate THEN 'Closed_Then_Reopened'
        WHEN QDP.AcceptedAnswerScore > 0 AND QDP.QuestionAnswerCount > 2 AND QDP.QuestionScore > 20 THEN 'High_Value_Question_Accepted'
        WHEN QDP.QuestionViewCount > 50000 AND QDP.QuestionAnswerCount = 0 THEN 'Viral_Unanswered_Question'
        WHEN QDP.QuestionAgeDays > 365 AND QDP.QuestionScore < 5 THEN 'Stale_Low_Engagement'
        ELSE 'Active_Or_Moderate'
    END AS QuestionLifecycleStatus,
    -- Window function: Rank users by their total post score within each TagPopularityQuintile
    RANK() OVER (
        PARTITION BY PTA.TagPopularityQuintile
        ORDER BY UAS.TotalPostsScore DESC, UAS.Reputation DESC
    ) AS UserRankInTagCategory,
    -- Window function: Calculate average question score for users over a rolling window (e.g., last 10 questions)
    AVG(QDP.QuestionScore) OVER (
        PARTITION BY UAS.UserId
        ORDER BY QDP.QuestionCreationDate
        ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
    ) AS RollingAvgQuestionScore,
    -- Conditional check for users who are very active but have negative net votes on their comments
    CASE
        WHEN UAS.TotalCommentsMade > 100 AND UAS.TotalCommentsScoreGiven < 0
             THEN 'Negative_Commenter'
        ELSE 'Regular_Commenter'
    END AS CommenterStatus
FROM UserActivitySummary AS UAS
LEFT JOIN QuestionDetailedPerformance AS QDP ON UAS.UserId = QDP.OwnerUserId
LEFT JOIN AnswerEngagementMetrics AS AEM ON QDP.QuestionId = AEM.QuestionId
LEFT JOIN PopularTagAnalysis AS PTA ON QDP.PrimaryTag = PTA.TagName
LEFT JOIN ModeratorInterventionSummary AS PMA ON QDP.QuestionId = PMA.PostId
WHERE
    UAS.Reputation >= 1000
    AND UAS.TotalPostsCreated >= 5
    AND QDP.QuestionId IS NOT NULL -- Only include users with at least one question in the QDP CTE
    AND (
        QDP.QuestionScore > 5 OR QDP.QuestionViewCount > 5000
    )
    AND (
        UAS.AboutMeLength IS NULL OR UAS.AboutMeLength > 10 -- NULL logic for AboutMe, ensure display name
    )
    AND UAS.DisplayName IS NOT NULL
ORDER BY QuestionImpactScore DESC, UserRankInTagCategory ASC
LIMIT 500;
