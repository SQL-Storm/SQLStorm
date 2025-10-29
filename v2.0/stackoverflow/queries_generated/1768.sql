-- {"query": "1768.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3910} 

WITH UserEngagement AS (
    -- CTE 1: Aggregates user-level metrics, including post counts, scores, and edit activity.
    -- Incorporates self-join to Posts for accepted answer tracking and NULL handling for potentially missing owner data.
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        MAX(p.LastActivityDate) AS LastPostActivity,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditsMade,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS TotalClosedPosts,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS TotalAcceptedAnswersGiven,
        AVG(CAST(COALESCE(p.ViewCount, 0) AS NUMERIC)) AS AvgPostViewCount,
        -- Calculate the fraction of answers that were accepted by the author of the question
        COALESCE(
            SUM(CASE WHEN p_parent.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) * 1.0 / NULLIF(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0),
            0.0
        ) AS AcceptedAnswerRatio
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        PostHistory ph ON u.Id = ph.UserId AND p.Id = ph.PostId
    LEFT JOIN
        Posts p_parent ON p.ParentId = p_parent.Id -- Self-join to identify accepted answers for answers (PostTypeId = 2)
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
RecentPostActivity AS (
    -- CTE 2: Identifies posts with recent activity, including complex string matching and a correlated subquery for recent comment scores.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        -- Calculate days since last activity using date arithmetic
        EXTRACT(EPOCH FROM (NOW() - p.LastActivityDate)) / 86400 AS DaysSinceLastActivity,
        -- Complex string expression: Check for specific tags or title patterns (case-insensitive)
        ((p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%') AND p.Title ILIKE '%performance%') AS IsPerformanceRelated,
        -- Correlated subquery: Sum of scores for comments made in the last 30 days on this specific post
        (SELECT SUM(c.Score) FROM Comments c WHERE c.PostId = p.Id AND c.CreationDate > NOW() - INTERVAL '30 days') AS RecentCommentScoreSum,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount
    FROM
        Posts p
    LEFT JOIN
        PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 1 -- Linked posts only
    WHERE
        p.LastActivityDate > NOW() - INTERVAL '90 days'
        AND p.PostTypeId IN (1, 2) -- Focus on Questions or Answers
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate, p.LastActivityDate, p.Title, p.Tags, p.CommentCount, p.FavoriteCount, p.ClosedDate
),
ModeratorActivitySummary AS (
    -- CTE 3: Analyzes moderator actions using various window functions (FIRST_VALUE, ROW_NUMBER, LAG) and NULL logic.
    SELECT
        ph.PostId,
        ph.UserId AS ModeratorUserId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS ActionDate,
        ph.Comment,
        FIRST_VALUE(ph.Text) OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS LatestActionText,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousActionDate,
        -- Calculate time difference in hours between current and previous moderator action
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) / 3600 AS HoursSincePreviousAction
    FROM
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) -- Specific moderator-related action types
        AND ph.UserId IS NOT NULL -- Actions by identified users (moderators)
        AND ph.CreationDate > NOW() - INTERVAL '1 year'
),
UserBadgeRank AS (
    -- CTE 4: Ranks users based on their gold badge count within their creation year using a window function.
    SELECT
        b.UserId,
        COUNT(b.Id) AS GoldBadges,
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY COUNT(b.Id) DESC) AS RankByGoldBadgesInYear
    FROM
        Badges b
    JOIN
        Users u ON b.UserId = u.Id
    WHERE
        b.Class = 1 -- Gold badges only
    GROUP BY
        b.UserId, EXTRACT(YEAR FROM u.CreationDate)
),
MainQueryBranch1 AS (
    -- Main Query Branch 1: Focuses on highly reputable users with significant recent activity and performance-related posts.
    SELECT
        ue.UserId,
        -- String expression and NULL logic: Provide a default display name for deleted users
        COALESCE(u.DisplayName, 'Deleted User (' || ue.UserId || ')') AS DisplayName,
        ue.Reputation,
        ue.UserCreationDate,
        ue.LastAccessDate,
        ue.TotalQuestions,
        ue.TotalAnswers,
        ue.TotalEditsMade,
        ue.TotalClosedPosts,
        ue.AcceptedAnswerRatio,
        COALESCE(rb.GoldBadges, 0) AS GoldBadges, -- COALESCE for users with no gold badges
        rb.RankByGoldBadgesInYear,
        MAX(rpa.DaysSinceLastActivity) AS MaxDaysSincePostActivity,
        -- Conditional aggregation using FILTER clause
        AVG(rpa.Score) FILTER (WHERE rpa.PostTypeId = 1) AS AvgQuestionScoreRecent,
        AVG(rpa.Score) FILTER (WHERE rpa.PostTypeId = 2) AS AvgAnswerScoreRecent,
        COUNT(DISTINCT rpa.PostId) AS TotalRecentActivePosts,
        SUM(CASE WHEN rpa.IsPerformanceRelated THEN 1 ELSE 0 END) AS PerformanceRelatedPostsCount,
        -- Correlated subquery: Checks if the user has recently answered questions from high-reputation users in specific locations.
        EXISTS (
            SELECT 1
            FROM Posts p_inner
            JOIN Users u_inner ON p_inner.OwnerUserId = u_inner.Id
            WHERE p_inner.PostTypeId = 2
              AND p_inner.OwnerUserId = ue.UserId
              AND p_inner.CreationDate > NOW() - INTERVAL '6 months'
              AND EXISTS (
                    SELECT 1
                    FROM Posts q_inner
                    WHERE q_inner.Id = p_inner.ParentId
                      AND q_inner.OwnerUserId != ue.UserId
                      AND q_inner.OwnerUserId IN (
                          SELECT u2.Id FROM Users u2 WHERE u2.Reputation > 5000 AND u2.Location IS NOT NULL AND u2.Location NOT LIKE '%earth%'
                      )
              )
        ) AS HasAnsweredHighReputationQuestionsRecently,
        SUM(CASE WHEN mas.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalClosedByModerator,
        SUM(CASE WHEN mas.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalReopenedByModerator,
        AVG(mas.HoursSincePreviousAction) AS AvgHoursBetweenModeratorActions,
        -- String expression and NULL logic: Average length of moderator comments, ignoring empty strings
        AVG(LENGTH(NULLIF(TRIM(mas.Comment), ''))) AS AvgModeratorCommentLength,
        -- Complex calculation: Ratio of edits made to total posts, handling division by zero
        CAST(ue.TotalEditsMade AS NUMERIC) / NULLIF(ue.TotalPosts, 0) AS EditToPostRatioOverall,
        'HighReputationPerformance' AS AnalysisCategory -- Categorize this branch's results
    FROM
        UserEngagement ue
    LEFT JOIN
        Users u ON ue.UserId = u.Id
    LEFT JOIN
        RecentPostActivity rpa ON ue.UserId = rpa.OwnerUserId
    LEFT JOIN
        ModeratorActivitySummary mas ON ue.UserId = mas.ModeratorUserId
    LEFT JOIN
        UserBadgeRank rb ON ue.UserId = rb.UserId
    WHERE
        ue.Reputation > 15000 -- Higher reputation threshold
        AND ue.TotalPosts > 20
        AND ue.LastAccessDate > NOW() - INTERVAL '6 months'
        AND NOT (u.AboutMe ILIKE '%bot%' OR u.DisplayName ILIKE '%test%') -- Exclude bot/test accounts
        AND COALESCE(rb.GoldBadges, 0) > 2 -- At least 3 gold badges
        AND EXISTS ( -- Non-correlated subquery: ensure user has at least one post with a very high score
            SELECT 1
            FROM Posts p_sub
            WHERE p_sub.OwnerUserId = ue.UserId
              AND p_sub.Score > 100
        )
    GROUP BY
        ue.UserId, u.DisplayName, ue.Reputation, ue.UserCreationDate, ue.LastAccessDate, ue.TotalQuestions, ue.TotalAnswers,
        ue.TotalEditsMade, ue.TotalClosedPosts, ue.AcceptedAnswerRatio, COALESCE(rb.GoldBadges,0), rb.RankByGoldBadgesInYear, ue.TotalPosts,
        u.AboutMe, u.DisplayName
    HAVING
        COUNT(DISTINCT rpa.PostId) > 5 -- At least 5 recent active posts
        AND SUM(CASE WHEN rpa.IsPerformanceRelated THEN 1 ELSE 0 END) > 0 -- Must have performance-related posts
        AND AVG(rpa.Score) FILTER (WHERE rpa.PostTypeId = 1) > 20 -- Good average question score
        AND (SUM(CASE WHEN mas.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) < SUM(CASE WHEN mas.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) * 2 OR SUM(CASE WHEN mas.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) = 0) -- Fewer closed posts than reopened, or no closed posts
),
MainQueryBranch2 AS (
    -- Main Query Branch 2: Focuses on users with high accepted answer ratios and significant moderator interaction, potentially for mentorship roles.
    SELECT
        ue.UserId,
        COALESCE(u.DisplayName, 'Deleted User (' || ue.UserId || ')') AS DisplayName,
        ue.Reputation,
        ue.UserCreationDate,
        ue.LastAccessDate,
        ue.TotalQuestions,
        ue.TotalAnswers,
        ue.TotalEditsMade,
        ue.TotalClosedPosts,
        ue.AcceptedAnswerRatio,
        COALESCE(rb.GoldBadges, 0) AS GoldBadges,
        rb.RankByGoldBadgesInYear,
        MAX(rpa.DaysSinceLastActivity) AS MaxDaysSincePostActivity,
        AVG(rpa.Score) FILTER (WHERE rpa.PostTypeId = 1) AS AvgQuestionScoreRecent,
        AVG(rpa.Score) FILTER (WHERE rpa.PostTypeId = 2) AS AvgAnswerScoreRecent,
        COUNT(DISTINCT rpa.PostId) AS TotalRecentActivePosts,
        SUM(CASE WHEN rpa.IsPerformanceRelated THEN 1 ELSE 0 END) AS PerformanceRelatedPostsCount,
        EXISTS ( -- Same correlated subquery as branch 1 for comparison
            SELECT 1
            FROM Posts p_inner
            JOIN Users u_inner ON p_inner.OwnerUserId = u_inner.Id
            WHERE p_inner.PostTypeId = 2
              AND p_inner.OwnerUserId = ue.UserId
              AND p_inner.CreationDate > NOW() - INTERVAL '6 months'
              AND EXISTS (
                    SELECT 1
                    FROM Posts q_inner
                    WHERE q_inner.Id = p_inner.ParentId
                      AND q_inner.OwnerUserId != ue.UserId
                      AND q_inner.OwnerUserId IN (
                          SELECT u2.Id FROM Users u2 WHERE u2.Reputation > 5000 AND u2.Location IS NOT NULL AND u2.Location NOT LIKE '%earth%'
                      )
              )
        ) AS HasAnsweredHighReputationQuestionsRecently,
        SUM(CASE WHEN mas.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalClosedByModerator,
        SUM(CASE WHEN mas.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalReopenedByModerator,
        AVG(mas.HoursSincePreviousAction) AS AvgHoursBetweenModeratorActions,
        AVG(LENGTH(NULLIF(TRIM(mas.Comment), ''))) AS AvgModeratorCommentLength,
        CAST(ue.TotalEditsMade AS NUMERIC) / NULLIF(ue.TotalPosts, 0) AS EditToPostRatioOverall,
        'MentorshipPotential' AS AnalysisCategory -- Categorize this branch's results
    FROM
        UserEngagement ue
    LEFT JOIN
        Users u ON ue.UserId = u.Id
    LEFT JOIN
        RecentPostActivity rpa ON ue.UserId = rpa.OwnerUserId
    LEFT JOIN
        ModeratorActivitySummary mas ON ue.UserId = mas.ModeratorUserId
    LEFT JOIN
        UserBadgeRank rb ON ue.UserId = rb.UserId
    WHERE
        ue.Reputation BETWEEN 1000 AND 15000 -- Mid-to-high reputation range
        AND ue.TotalAnswers > 50 -- Significant number of answers
        AND ue.LastAccessDate > NOW() - INTERVAL '9 months'
        AND u.Location IS NOT NULL AND LENGTH(TRIM(u.Location)) > 0 -- Users with specified, non-empty location
        AND ue.AcceptedAnswerRatio > 0.7 -- Very high accepted answer ratio
        AND (ue.UserViews > 1000 OR ue.UserUpVotes > 500)
    GROUP BY
        ue.UserId, u.DisplayName, ue.Reputation, ue.UserCreationDate, ue.LastAccessDate, ue.TotalQuestions, ue.TotalAnswers,
        ue.TotalEditsMade, ue.TotalClosedPosts, ue.AcceptedAnswerRatio, COALESCE(rb.GoldBadges,0), rb.RankByGoldBadgesInYear, ue.TotalPosts,
        u.AboutMe, u.DisplayName
    HAVING
        ue.TotalAnswers > 100 -- More stringent answer count
        AND (SUM(CASE WHEN mas.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) > 5 OR SUM(CASE WHEN mas.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) > 5) -- Significant moderator interactions (either closes or reopens)
        AND AVG(LENGTH(NULLIF(TRIM(mas.Comment), ''))) IS NOT NULL -- Must have at least one non-empty moderator comment
)
-- Set operator: Combines results from both analysis branches.
SELECT * FROM MainQueryBranch1
UNION ALL
SELECT * FROM MainQueryBranch2
ORDER BY Reputation DESC, TotalRecentActivePosts DESC
LIMIT 200 OFFSET 20;
