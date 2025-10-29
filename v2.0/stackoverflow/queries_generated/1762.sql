-- {"query": "1762.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4547} 

WITH UserBaseStats AS (
    -- Gathers fundamental user data, calculates user tenure, and determines the last content activity date.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        u.Views AS ProfileViews,
        u.Location,
        u.AboutMe,
        EXTRACT(YEAR FROM u.CreationDate) AS CreationYear,
        AGE(CURRENT_DATE, u.CreationDate) AS AccountAge, -- PostgreSQL-specific for AGE
        COALESCE(u.WebsiteUrl, 'N/A') AS UserWebsiteUrl,
        -- Correlated subquery to find the user's most recent post or comment activity
        (
            SELECT MAX(activity_date)
            FROM (
                SELECT p.CreationDate AS activity_date
                FROM Posts p
                WHERE p.OwnerUserId = u.Id
                UNION ALL
                SELECT c.CreationDate AS activity_date
                FROM Comments c
                WHERE c.UserId = u.Id
            ) AS user_activities
        ) AS LastContentActivityDate
    FROM
        Users u
    WHERE
        u.Reputation > 750 -- Filtering for moderately established users
        AND LENGTH(COALESCE(u.AboutMe, '')) > 20 -- Users with some 'About Me' description
),
PostAggregations AS (
    -- Aggregates post-related metrics for each user, differentiating between questions and answers.
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        SUM(p.ViewCount) AS TotalPostViewCount,
        SUM(p.FavoriteCount) AS TotalFavoriteCount,
        SUM(p.AnswerCount) AS TotalAnswerCountForQuestions,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
        MAX(p.CreationDate) AS LatestPostDate
    FROM
        Posts p
    WHERE
        p.OwnerUserId IS NOT NULL
        AND p.CreationDate >= (CURRENT_DATE - INTERVAL '5 year') -- Only recent posts
    GROUP BY
        p.OwnerUserId
),
CommentAggregations AS (
    -- Aggregates comment-related metrics for each user.
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM
        Comments c
    WHERE
        c.UserId IS NOT NULL
        AND c.CreationDate >= (CURRENT_DATE - INTERVAL '3 year')
    GROUP BY
        c.UserId
),
BadgeSummary AS (
    -- Summarizes badge counts by class for each user, including tag-based badges.
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges
    FROM
        Badges b
    WHERE
        b.Date >= (CURRENT_DATE - INTERVAL '4 year')
    GROUP BY
        b.UserId
),
PostHistoryEdits AS (
    -- Analyzes user's contributions to post editing, including time differences between consecutive edits.
    SELECT
        ph.UserId,
        ph.PostId,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate) AS PrevEditDate,
        -- Calculate time elapsed since previous edit by the same user on the same post
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate))) / 3600 AS HoursSincePrevEdit -- in hours
    FROM
        PostHistory ph
    WHERE
        ph.UserId IS NOT NULL
        AND ph.PostHistoryTypeId IN (4, 5, 6, 8) -- Edit Title, Edit Body, Edit Tags, Rollback Body
        AND ph.CreationDate >= (CURRENT_DATE - INTERVAL '2 year')
),
UserEditStats AS (
    -- Aggregates editing statistics per user.
    SELECT
        phe.UserId,
        COUNT(phe.PostId) AS TotalEditsMade,
        COUNT(DISTINCT phe.PostId) AS UniquePostsEdited,
        AVG(phe.HoursSincePrevEdit) FILTER (WHERE phe.HoursSincePrevEdit IS NOT NULL) AS AvgHoursBetweenEdits, -- PostgreSQL-specific FILTER
        SUM(CASE WHEN phe.PostHistoryTypeId = 8 THEN 1 ELSE 0 END) AS TotalRollbacks
    FROM
        PostHistoryEdits phe
    GROUP BY
        phe.UserId
),
UserTagEngagement AS (
    -- Calculates user engagement with specific high-value tags, involving array manipulation.
    SELECT
        p.OwnerUserId AS UserId,
        LOWER(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'))) AS TagName, -- PostgreSQL-specific string and array functions
        COUNT(DISTINCT p.Id) AS PostsInTag,
        SUM(p.Score) AS ScoreInTag,
        MAX(p.CreationDate) AS LatestPostInTag
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 -- Only questions have tags
        AND p.OwnerUserId IS NOT NULL
        AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 -- Ensure tags are present
    GROUP BY
        p.OwnerUserId,
        LOWER(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')))
    HAVING
        LOWER(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'))) IN ('sql', 'performance', 'javascript', 'python', 'database', 'c#', 'java', 'web-development')
),
UserOverallEngagement AS (
    -- Combines all user-level aggregations and calculates a composite "influence score".
    SELECT
        ubs.UserId,
        ubs.DisplayName,
        ubs.Reputation,
        ubs.CreationDate,
        ubs.LastAccessDate,
        ubs.LastContentActivityDate,
        COALESCE(pa.TotalPostsOwned, 0) AS TotalPostsOwned,
        COALESCE(pa.TotalQuestions, 0) AS TotalQuestions,
        COALESCE(pa.TotalAnswers, 0) AS TotalAnswers,
        COALESCE(pa.TotalQuestionScore, 0) AS TotalQuestionScore,
        COALESCE(pa.TotalAnswerScore, 0) AS TotalAnswerScore,
        COALESCE(pa.TotalPostViewCount, 0) AS TotalPostViewCount,
        COALESCE(pa.TotalFavoriteCount, 0) AS TotalFavoriteCount,
        COALESCE(pa.TotalAnswerCountForQuestions, 0) AS TotalAnswerCountForQuestions,
        COALESCE(pa.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(ca.TotalComments, 0) AS TotalComments,
        COALESCE(ca.TotalCommentScore, 0) AS TotalCommentScore,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(bs.TotalBadges, 0) AS TotalBadges,
        COALESCE(bs.TagBasedBadges, 0) AS TotalTagBasedBadges,
        COALESCE(ues.TotalEditsMade, 0) AS TotalEditsMade,
        COALESCE(ues.UniquePostsEdited, 0) AS UniquePostsEdited,
        COALESCE(ues.AvgHoursBetweenEdits, 0) AS AvgHoursBetweenEdits,
        COALESCE(ues.TotalRollbacks, 0) AS TotalRollbacks,
        ubs.ProfileViews,
        ubs.Location,
        ubs.AboutMe,
        -- Complex calculation for a composite "influence score" with weighted metrics
        (
            ubs.Reputation * 0.45
            + COALESCE(pa.TotalQuestionScore * 0.2, 0)
            + COALESCE(pa.TotalAnswerScore * 0.15, 0)
            + COALESCE(ca.TotalCommentScore * 0.05, 0)
            + COALESCE(bs.GoldBadges * 150, 0)
            + COALESCE(bs.SilverBadges * 30, 0)
            + COALESCE(ues.TotalEditsMade * 7, 0)
            + COALESCE(pa.TotalFavoriteCount * 0.75, 0)
            - COALESCE(ues.TotalRollbacks * 10, 0) -- Penalize rollbacks
            + (ubs.TotalUpVotesGiven - ubs.TotalDownVotesGiven) * 0.01 -- Consider explicit votes given by user
        ) AS CompositeInfluenceScore
    FROM
        UserBaseStats ubs
    LEFT JOIN PostAggregations pa ON ubs.UserId = pa.UserId
    LEFT JOIN CommentAggregations ca ON ubs.UserId = ca.UserId
    LEFT JOIN BadgeSummary bs ON ubs.UserId = bs.UserId
    LEFT JOIN UserEditStats ues ON ubs.UserId = ues.UserId
),
RankedUsers AS (
    -- Ranks users based on their CompositeInfluenceScore and calculates relative metrics using window functions.
    SELECT
        uoe.*,
        RANK() OVER (ORDER BY uoe.CompositeInfluenceScore DESC, uoe.Reputation DESC) AS InfluenceRank,
        NTILE(10) OVER (ORDER BY uoe.Reputation DESC) AS ReputationDecile,
        AVG(uoe.Reputation) OVER (PARTITION BY uoe.CreationYear) AS AvgReputationInCreationYear, -- Average reputation of users created in the same year
        COALESCE(uoe.TotalAnswers * 1.0 / NULLIF(uoe.TotalQuestions, 0), 0.0) AS AnswerToQuestionRatio, -- Handle division by zero
        COALESCE(uoe.TotalEditsMade * 1.0 / NULLIF(uoe.TotalPostsOwned, 0), 0.0) AS EditsPerPostRatio,
        -- A custom categorization based on various activity and reputation thresholds
        CASE
            WHEN uoe.Reputation > 75000 AND uoe.TotalPostsOwned > 750 AND uoe.GoldBadges > 5 THEN 'Elite Contributor'
            WHEN uoe.Reputation > 25000 AND uoe.TotalPostsOwned > 200 AND uoe.GoldBadges > 0 THEN 'Veteran Expert'
            WHEN uoe.TotalAnswers > 100 AND uoe.AvgAnswerScore > 15 AND uoe.TotalTagBasedBadges > 5 THEN 'Specialized Answerer'
            WHEN uoe.TotalQuestions > 50 AND uoe.TotalFavoriteCount > 100 AND uoe.TotalComments > 50 THEN 'Engaged Questioner'
            WHEN uoe.TotalEditsMade > 50 AND uoe.AvgHoursBetweenEdits < 24 THEN 'Dedicated Editor'
            ELSE 'Active Participant'
        END AS UserContributionCategory,
        -- String expression using CONCAT_WS and NULL logic for location
        CONCAT_WS(' | ', uoe.DisplayName, COALESCE(uoe.Location, 'Unknown Location')) AS UserIdentifier
    FROM
        UserOverallEngagement uoe
),
TopSpecificTagUsers AS (
    -- Identifies users with significant contributions to the pre-defined high-value tags.
    SELECT
        ute.UserId,
        COUNT(DISTINCT ute.TagName) AS NumberOfSpecificTags,
        SUM(CASE WHEN ute.TagName = 'sql' THEN ute.PostsInTag ELSE 0 END) AS SqlPosts,
        SUM(CASE WHEN ute.TagName = 'performance' THEN ute.PostsInTag ELSE 0 END) AS PerformancePosts,
        SUM(CASE WHEN ute.TagName = 'javascript' THEN ute.PostsInTag ELSE 0 END) AS JavascriptPosts,
        SUM(ute.ScoreInTag) AS TotalScoreInSpecificTags
    FROM
        UserTagEngagement ute
    GROUP BY
        ute.UserId
    HAVING
        COUNT(DISTINCT ute.TagName) >= 2 -- Active in at least two specific tags
        AND SUM(ute.ScoreInTag) > 75 -- Minimum aggregated score for relevance in these tags
)
-- Main Query - Combining RankedUsers with TopSpecificTagUsers and applying complex filters,
-- then using UNION ALL to include another distinct group of users.
SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.InfluenceRank,
    ru.ReputationDecile,
    ru.UserContributionCategory,
    ru.UserIdentifier,
    ru.TotalPostsOwned,
    ru.TotalQuestions,
    ru.TotalAnswers,
    ru.TotalEditsMade,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.CompositeInfluenceScore,
    ru.AnswerToQuestionRatio,
    ru.EditsPerPostRatio,
    COALESCE(tstu.NumberOfSpecificTags, 0) AS TagsOfExpertiseCount,
    COALESCE(tstu.SqlPosts, 0) AS SqlPostsContribution,
    COALESCE(tstu.PerformancePosts, 0) AS PerformancePostsContribution,
    COALESCE(tstu.JavascriptPosts, 0) AS JavascriptPostsContribution,
    -- Complicated expression involving string length and date difference for user profile assessment
    LENGTH(COALESCE(ru.AboutMe, '')) AS AboutMeLength,
    CASE
        WHEN LENGTH(COALESCE(ru.AboutMe, '')) > 750 AND (CURRENT_DATE - ru.CreationDate) > INTERVAL '5 year' THEN 'Verbose & Established Veteran'
        WHEN ru.LastContentActivityDate IS NULL OR (CURRENT_DATE - ru.LastContentActivityDate) > INTERVAL '1.5 year' THEN 'Potentially Inactive User'
        WHEN ru.Reputation < ru.AvgReputationInCreationYear * 0.8 THEN 'Underperforming for Cohort'
        ELSE 'Consistent Contributor'
    END AS UserEngagementProfileStatus
FROM
    RankedUsers ru
LEFT JOIN TopSpecificTagUsers tstu ON ru.UserId = tstu.UserId
WHERE
    -- Complex predicate with nested AND/OR logic, string functions, and NULL checks
    (
        (ru.InfluenceRank <= 50 OR ru.ReputationDecile = 1 AND ru.GoldBadges >= 1)
        AND ru.TotalPostsOwned > 75
        AND ru.TotalEditsMade > 20
        AND ru.AvgAnswerScore > 10
        AND (LOWER(ru.Location) LIKE '%london%' OR LOWER(ru.Location) LIKE '%new york%')
    )
    OR
    (
        ru.TotalUpVotesGiven > 7500
        AND ru.AnswerToQuestionRatio > 2.0 -- Significantly more answers than questions
        AND ru.EditsPerPostRatio > 0.5 -- Actively editing their posts
        AND ru.UserId NOT IN (SELECT UserId FROM TopSpecificTagUsers WHERE SqlPosts > 5 OR PerformancePosts > 5) -- Exclude users highly specialized in these tags
        AND (ru.AboutMe IS NOT NULL AND LENGTH(ru.AboutMe) > 100)
    )
    OR
    (
        ru.TotalTagBasedBadges > 10
        AND ru.TotalQuestions > 20
        AND ru.TotalComments > 50
        AND ru.LastAccessDate >= (CURRENT_DATE - INTERVAL '6 months')
        AND ru.TotalRollbacks = 0 -- No rollbacks, indicating high quality edits
    )

UNION ALL

-- A separate branch to identify users who are highly active in specific tags but might not be top-ranked overall,
-- demonstrating a different type of expertise, using a set operator for distinct criteria.
SELECT
    uoe.UserId,
    uoe.DisplayName,
    uoe.Reputation,
    NULL AS InfluenceRank, -- Not part of the main influence ranking in this branch
    NULL AS ReputationDecile,
    'Tag Specialist' AS UserContributionCategory,
    CONCAT_WS(' | ', uoe.DisplayName, COALESCE(uoe.Location, 'Unknown Location')) AS UserIdentifier,
    uoe.TotalPostsOwned,
    uoe.TotalQuestions,
    uoe.TotalAnswers,
    uoe.TotalEditsMade,
    uoe.GoldBadges,
    uoe.SilverBadges,
    uoe.BronzeBadges,
    uoe.CompositeInfluenceScore,
    COALESCE(uoe.TotalAnswers * 1.0 / NULLIF(uoe.TotalQuestions, 0), 0.0) AS AnswerToQuestionRatio,
    COALESCE(uoe.TotalEditsMade * 1.0 / NULLIF(uoe.TotalPostsOwned, 0), 0.0) AS EditsPerPostRatio,
    COALESCE(tstu_inner.NumberOfSpecificTags, 0) AS TagsOfExpertiseCount,
    COALESCE(tstu_inner.SqlPosts, 0) AS SqlPostsContribution,
    COALESCE(tstu_inner.PerformancePosts, 0) AS PerformancePostsContribution,
    COALESCE(tstu_inner.JavascriptPosts, 0) AS JavascriptPostsContribution,
    LENGTH(COALESCE(uoe.AboutMe, '')) AS AboutMeLength,
    'Highly Focused Contributor' AS UserEngagementProfileStatus
FROM
    UserOverallEngagement uoe
INNER JOIN TopSpecificTagUsers tstu_inner ON uoe.UserId = tstu_inner.UserId
WHERE
    uoe.Reputation BETWEEN 2000 AND 20000 -- Within a specific reputation range for specialists
    AND tstu_inner.NumberOfSpecificTags >= 3 -- Active in at least three specific tags
    AND tstu_inner.TotalScoreInSpecificTags > 200 -- High score within these tags
    AND uoe.TotalPostsOwned > 30 -- Minimum general contribution
    AND uoe.LastAccessDate >= (CURRENT_DATE - INTERVAL '1 year') -- Recently active
ORDER BY
    Reputation DESC, CompositeInfluenceScore DESC, TagsOfExpertiseCount DESC
LIMIT 750;
