-- {"query": "1782.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3365} 

WITH UserContributionSummary AS (
    -- Summarizes user activity, post counts, and overall scores.
    -- Uses LEFT JOIN to include users who might not have posts or comments.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(SUM(P.ViewCount), 0) AS TotalPostViews,
        COALESCE(SUM(P.FavoriteCount), 0) AS TotalFavorites,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
PostEditMetrics AS (
    -- Calculates edit frequency and type for individual posts.
    -- Excludes community/system edits by checking PH.UserId IS NOT NULL.
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalEdits,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS MajorEdits, -- Edit Title, Body, Tags
        MIN(PH.CreationDate) AS FirstEditDate,
        MAX(PH.CreationDate) AS LastEditDate
    FROM
        PostHistory PH
    WHERE
        PH.PostHistoryTypeId BETWEEN 1 AND 25 -- Focus on common edit/status history types
        AND PH.UserId IS NOT NULL
    GROUP BY
        PH.PostId
),
UserPostEditAggregates AS (
    -- Aggregates post edit and history metrics per user, specifically for their questions.
    -- Includes average edit interval and total reopen count.
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT P.Id) AS UserQuestionsWithEdits,
        -- Calculates average days between edits for questions, using NULLIF to prevent division by zero.
        -- Uses FILTER clause for conditional aggregation.
        AVG(EXTRACT(EPOCH FROM (PEM.LastEditDate - PEM.FirstEditDate)) / (86400.0 * NULLIF(PEM.TotalEdits - 1, 0))) FILTER (WHERE PEM.TotalEdits > 1) AS AvgEditIntervalDaysPerUser,
        COALESCE(SUM(PEM.MajorEdits), 0) AS TotalMajorEditsOnUserQuestions,
        COALESCE(SUM(CASE WHEN PH_REOPEN.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Reopened') THEN 1 ELSE 0 END), 0) AS TotalReopensForUserQuestions
    FROM
        Posts P
    JOIN PostEditMetrics PEM ON P.Id = PEM.PostId
    -- Outer join for reopen history, as not all posts are reopened.
    LEFT JOIN PostHistory PH_REOPEN ON P.Id = PH_REOPEN.PostId AND PH_REOPEN.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Reopened')
    WHERE
        P.PostTypeId = 1 -- Only consider questions for these metrics
        AND P.OwnerUserId IS NOT NULL
    GROUP BY
        P.OwnerUserId
),
UserBadgeAwards AS (
    -- Summarizes badge counts and class per user, includes an array of all badge names.
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        ARRAY_AGG(DISTINCT B.Name ORDER BY B.Name) AS AllBadgeNames -- String array of badge names
    FROM
        Badges B
    GROUP BY
        B.UserId
),
AnswerQualityMetrics AS (
    -- Identifies top answers per question based on score and creation date,
    -- and retrieves the owner's reputation using a correlated subquery.
    SELECT
        P_A.Id AS AnswerId,
        P_A.ParentId AS QuestionId,
        P_A.OwnerUserId AS AnswerOwnerUserId,
        P_A.Score AS AnswerScore,
        -- Window function to rank answers for each question.
        ROW_NUMBER() OVER (PARTITION BY P_A.ParentId ORDER BY P_A.Score DESC, P_A.CreationDate ASC) AS Rnk_AnswerScore
    FROM
        Posts P_A
    WHERE
        P_A.PostTypeId = 2
),
DuplicatePostInfo AS (
    -- Gathers information about questions marked as duplicates.
    SELECT
        PL.PostId AS SourcePostId,
        PL.RelatedPostId AS DuplicateOfPostId
    FROM
        PostLinks PL
    WHERE
        PL.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Duplicate')
),
UserTagContributions AS (
    -- Aggregates scores for tags associated with a user's questions.
    -- Uses string_to_array and UNNEST for tag parsing, as specified in the schema.
    SELECT
        P.OwnerUserId AS UserId,
        UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')) AS TagName,
        SUM(P.Score) AS TagScoreSum
    FROM
        Posts P
    WHERE
        P.PostTypeId = 1 AND P.Tags IS NOT NULL AND P.Tags != ''
    GROUP BY
        P.OwnerUserId, UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))
)
-- Main query to find influential users based on a complex scoring model.
SELECT
    UCS.UserId,
    UCS.DisplayName,
    UCS.Reputation,
    UCS.TotalQuestions,
    UCS.TotalAnswers,
    UCS.TotalPostScore,
    UCS.TotalPostViews,
    UBA.TotalBadges,
    UBA.GoldBadges,
    -- Comprehensive User Influence Score calculation, incorporating various factors
    -- and demonstrating complex arithmetic expressions and correlated subqueries.
    (
        UCS.Reputation * 0.5 -- Reputation has a strong weight
        + UCS.TotalPostScore * 0.1 -- Post scores contribute
        + (UCS.TotalPostViews / 100.0) * 0.005 -- Scaled views contribute
        + UCS.TotalFavorites * 0.2 -- Favorite counts for questions
        + (UBA.GoldBadges * 100.0) -- Gold badges give a significant boost
        + COALESCE((SELECT SUM(AQM.AnswerScore) FROM AnswerQualityMetrics AQM WHERE AQM.AnswerOwnerUserId = UCS.UserId AND AQM.Rnk_AnswerScore = 1 AND AQM.AnswerScore > 0), 0.0) * 0.3 -- Sum of scores of their best answers
        + COALESCE((SELECT SUM(UTC.TagScoreSum) FROM UserTagContributions UTC WHERE UTC.UserId = UCS.UserId ORDER BY UTC.TagScoreSum DESC LIMIT 3), 0.0) * 0.05 -- Contribution from top 3 tags
        + COALESCE((SELECT COUNT(DISTINCT DP.SourcePostId) FROM DuplicatePostInfo DP WHERE DP.SourcePostId IN (SELECT P_Q_INNER.Id FROM Posts P_Q_INNER WHERE P_Q_INNER.OwnerUserId = UCS.UserId AND P_Q_INNER.PostTypeId = 1)), 0.0) * -50.0 -- Significant penalty for questions marked as duplicate
        + COALESCE(UPEA.TotalMajorEditsOnUserQuestions, 0.0) * 0.1 -- Reward for owned questions that received major edits by others
    ) AS UserInfluenceScore,
    -- Window function: Ranks users by their calculated influence score.
    DENSE_RANK() OVER (ORDER BY (
        UCS.Reputation * 0.5
        + UCS.TotalPostScore * 0.1
        + (UCS.TotalPostViews / 100.0) * 0.005
        + UCS.TotalFavorites * 0.2
        + (UBA.GoldBadges * 100.0)
        + COALESCE((SELECT SUM(AQM.AnswerScore) FROM AnswerQualityMetrics AQM WHERE AQM.AnswerOwnerUserId = UCS.UserId AND AQM.Rnk_AnswerScore = 1 AND AQM.AnswerScore > 0), 0.0) * 0.3
        + COALESCE((SELECT SUM(UTC.TagScoreSum) FROM UserTagContributions UTC WHERE UTC.UserId = UCS.UserId ORDER BY UTC.TagScoreSum DESC LIMIT 3), 0.0) * 0.05
        + COALESCE((SELECT COUNT(DISTINCT DP.SourcePostId) FROM DuplicatePostInfo DP WHERE DP.SourcePostId IN (SELECT P_Q_INNER.Id FROM Posts P_Q_INNER WHERE P_Q_INNER.OwnerUserId = UCS.UserId AND P_Q_INNER.PostTypeId = 1)), 0.0) * -50.0
        + COALESCE(UPEA.TotalMajorEditsOnUserQuestions, 0.0) * 0.1
    ) DESC) AS UserInfluenceRank,
    -- Average days between edits for a user's questions, handled by CTE.
    COALESCE(UPEA.AvgEditIntervalDaysPerUser, 0.0) AS AvgEditIntervalDaysForQuestions,
    COALESCE(UPEA.TotalReopensForUserQuestions, 0) AS ReopenCountForQuestions,
    -- Correlated subquery to find the most frequent editor for any question owned by this user.
    (
        SELECT U_EDITOR.DisplayName
        FROM Posts P_Q_INNER
        JOIN PostHistory PH_INNER ON P_Q_INNER.Id = PH_INNER.PostId
        JOIN Users U_EDITOR ON PH_INNER.UserId = U_EDITOR.Id
        WHERE P_Q_INNER.OwnerUserId = UCS.UserId
          AND P_Q_INNER.PostTypeId = 1
          AND PH_INNER.PostHistoryTypeId IN (4, 5, 6) -- Major edits
        GROUP BY U_EDITOR.DisplayName
        ORDER BY COUNT(PH_INNER.Id) DESC, MAX(U_EDITOR.Reputation) DESC
        LIMIT 1
    ) AS MostFrequentQuestionEditorAcrossUserPosts,
    -- Conditional expression using an EXISTS correlated subquery for user impact status.
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM Posts P_Q_HIGH
            WHERE P_Q_HIGH.OwnerUserId = UCS.UserId
              AND P_Q_HIGH.PostTypeId = 1
              AND P_Q_HIGH.ViewCount >= 1000
              AND P_Q_HIGH.AcceptedAnswerId IS NOT NULL
        ) THEN 'HighImpactQuestioner'
        ELSE 'NormalQuestioner'
    END AS QuestionerImpactStatus,
    -- String expression: converts location to uppercase and truncates, handles NULL with COALESCE.
    UPPER(LEFT(COALESCE(U.Location, 'Unknown Region'), 15)) AS UserLocationRegion,
    -- Non-correlated scalar subquery: Average score of recent 'optimization' or 'performance' related posts.
    (
        SELECT COALESCE(AVG(P_OPT.Score), 0)
        FROM Posts P_OPT
        WHERE P_OPT.PostTypeId IN (1, 2)
          AND (P_OPT.Body ILIKE '%optimization%' OR P_OPT.Tags ILIKE '%<performance>%') -- Case-insensitive string matching
          AND P_OPT.Score > 0
          AND P_OPT.CreationDate > (NOW() - INTERVAL '1 year')
    ) AS AvgOptimizationRelatedPostScoreLastYear,
    -- Date/Time calculation: Age function to find time since last access.
    AGE(NOW(), U.LastAccessDate) AS TimeSinceLastAccess,
    -- String expression: Converts an array of badge names into a comma-separated string.
    ARRAY_TO_STRING(UBA.AllBadgeNames, ', ') AS UserBadgeList
FROM
    Users U
LEFT JOIN UserContributionSummary UCS ON U.Id = UCS.UserId
LEFT JOIN UserBadgeAwards UBA ON U.Id = UBA.UserId
LEFT JOIN UserPostEditAggregates UPEA ON U.Id = UPEA.UserId -- Join the aggregated edit metrics
WHERE
    UCS.Reputation >= 500 -- Filter for users with significant reputation.
    AND UCS.TotalPosts > 0 -- Ensure the user has at least one post.
    AND U.LastAccessDate >= (NOW() - INTERVAL '3 months') -- Filter for recently active users.
    -- Complex predicate using OR logic for additional filtering.
    AND (
        U.WebsiteUrl IS NOT NULL -- User has a website
        OR U.Location ILIKE '%united states%' -- Or is located in the United States
        OR UBA.GoldBadges > 0 -- Or has earned at least one gold badge
    )
    AND UCS.DisplayName IS NOT NULL AND UCS.DisplayName != '' -- Exclude users without a proper display name.
GROUP BY
    UCS.UserId, UCS.DisplayName, UCS.Reputation, UCS.TotalQuestions, UCS.TotalAnswers,
    UCS.TotalPostScore, UCS.TotalPostViews, UCS.TotalFavorites, UBA.TotalBadges, UBA.GoldBadges,
    U.Location, U.LastAccessDate, UPEA.AvgEditIntervalDaysPerUser, UPEA.TotalMajorEditsOnUserQuestions,
    UPEA.TotalReopensForUserQuestions, UBA.AllBadgeNames, UCS.UserCreationDate
HAVING
    UCS.TotalQuestions > 0 OR UCS.TotalAnswers > 0 -- Must have authored at least one question or answer.
ORDER BY
    UserInfluenceScore DESC, U.Reputation DESC, AGE(NOW(), UCS.UserCreationDate) ASC -- Sort by influence, reputation, then account age (older first).
LIMIT 1000;
