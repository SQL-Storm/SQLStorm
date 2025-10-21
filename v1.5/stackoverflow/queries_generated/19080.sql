-- {"query": "19080.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3830} 

WITH UserPostStats AS (
    -- Aggregates post-related statistics for each user, including initial creation and edit counts.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.CreationDate AS UserCreationDate,
        u.Reputation,
        u.Views AS UserProfileViews,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(p.Score), 0.0) AS AvgPostScore,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId = u.Id THEN p.Id ELSE NULL END) AS EditedPostsCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId = u.Id THEN 1 ELSE NULL END) AS TotalEditsMade,
        -- Calculate the reputation gain from accepted answers
        SUM(CASE WHEN p.Id = q.AcceptedAnswerId AND p.OwnerUserId = u.Id THEN 15 ELSE 0 END) AS ReputationFromAcceptedAnswers
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory AS ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6, 8) -- Edit Title, Edit Body, Edit Tags, Rollback Body
    LEFT JOIN Posts AS q ON p.ParentId = q.Id AND p.PostTypeId = 2 -- Link answers back to questions for AcceptedAnswerId check
    GROUP BY u.Id, u.DisplayName, u.CreationDate, u.Reputation, u.Views
),
UserCommentActivity AS (
    -- Summarizes comment-related activities and statistics for each user.
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate,
        -- Correlated subquery: Find the text of the most recent highly-scored comment by this user
        (
            SELECT sub_c.Text
            FROM Comments AS sub_c
            WHERE sub_c.UserId = c.UserId
              AND sub_c.CreationDate = MAX(c.CreationDate)
              AND sub_c.Score > 0
            ORDER BY sub_c.Id DESC
            LIMIT 1
        ) AS TextOfLastPositiveComment
    FROM Comments AS c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserBadgeSummary AS (
    -- Provides a breakdown of badges acquired by users, including timing and ranking.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MIN(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) AS FirstGoldBadgeDate,
        MIN(b.Date) AS FirstBadgeDate,
        -- Window function: Rank users based on their gold badge count, then silver, then bronze for tie-breaking
        RANK() OVER (ORDER BY SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) DESC, SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) DESC, SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) DESC) AS BadgeClassRank
    FROM Badges AS b
    GROUP BY b.UserId
),
PostTagAnalysis AS (
    -- Analyzes tag usage for questions, extracting the first tag and counting its occurrences.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        TRIM(LOWER(SPLIT_PART(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><', 1))) AS FirstParsedTag
    FROM Posts AS p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
),
UserTagProficiency AS (
    -- Determines the top tag for each user based on their question contributions.
    SELECT
        pta.OwnerUserId AS UserId,
        pta.FirstParsedTag AS TopTag,
        COUNT(pta.PostId) AS TagPostCount,
        -- Window function: Rank tags for each user
        ROW_NUMBER() OVER (PARTITION BY pta.OwnerUserId ORDER BY COUNT(pta.PostId) DESC, pta.FirstParsedTag ASC) AS TagRank
    FROM PostTagAnalysis AS pta
    GROUP BY pta.OwnerUserId, pta.FirstParsedTag
    HAVING COUNT(pta.PostId) >= 5 -- Only consider tags with at least 5 posts
),
PostLifeCycleMetrics AS (
    -- Calculates various metrics related to the life cycle of a question post, including edit frequency and closure events.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS CurrentPostScore,
        p.ViewCount,
        p.AnswerCount,
        p.Title,
        p.Tags,
        p.ClosedDate,
        -- Count specific post history events
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseEvents,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.Id END) AS ReopenEvents,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id ELSE NULL END) AS TotalPostEditEvents,
        -- Calculate time difference between creation and last activity date (in hours)
        EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 3600 AS HoursToLastActivity,
        -- Determine if the post body was significantly altered (check original vs last body history if available)
        MAX(CASE WHEN ph_initial.PostHistoryTypeId = 2 THEN LENGTH(ph_initial.Text) ELSE NULL END) AS InitialBodyLength,
        MAX(CASE WHEN ph_last.PostHistoryTypeId = 5 AND ph_last.RevisionGUID = p.LastEditorUserId THEN LENGTH(ph_last.Text) ELSE NULL END) AS LastEditBodyLength, -- Simplistic, last edit by editor
        -- Subquery to check for specific link types related to this post
        EXISTS (
            SELECT 1 FROM PostLinks AS pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3 -- Duplicate link
        ) AS HasDuplicateLink,
        -- String expression: Check if title or body mentions "best practices" or "performance"
        (CASE
            WHEN LOWER(p.Title) LIKE '%best practices%' OR LOWER(p.Body) LIKE '%best practices%' THEN TRUE
            WHEN LOWER(p.Title) LIKE '%performance%' OR LOWER(p.Body) LIKE '%performance%' THEN TRUE
            ELSE FALSE
        END) AS PerformanceRelatedContent
    FROM Posts AS p
    LEFT JOIN PostHistory AS ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (10, 11, 4, 5, 6)
    LEFT JOIN PostHistory AS ph_initial ON p.Id = ph_initial.PostId AND ph_initial.PostHistoryTypeId = 2
    LEFT JOIN PostHistory AS ph_last ON p.Id = ph_last.PostId AND ph_last.PostHistoryTypeId = 5
    WHERE p.PostTypeId = 1 -- Focus on questions
    GROUP BY
        p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.Title, p.Tags, p.ClosedDate, p.LastActivityDate, p.LastEditorUserId
),
UserConsolidatedData AS (
    -- Combines all user-centric CTEs into a single, comprehensive dataset.
    SELECT
        ups.UserId,
        ups.DisplayName,
        ups.Reputation,
        ups.UserProfileViews,
        ups.UserCreationDate,
        ups.TotalPosts,
        ups.TotalQuestions,
        ups.TotalAnswers,
        ups.TotalPostScore,
        ups.AvgPostScore,
        COALESCE(uca.TotalComments, 0) AS TotalComments,
        COALESCE(uca.TotalCommentScore, 0) AS TotalCommentScore,
        COALESCE(uca.AvgCommentScore, 0.0) AS AvgCommentScore,
        ubs.TotalBadges,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.FirstGoldBadgeDate,
        ubs.FirstBadgeDate,
        ubs.BadgeClassRank,
        ups.EditedPostsCount,
        ups.TotalEditsMade,
        ups.ReputationFromAcceptedAnswers,
        COALESCE(utp.TopTag, 'N/A') AS MostProficientTag,
        COALESCE(utp.TagPostCount, 0) AS MostProficientTagPosts,
        -- Calculate overall activity duration since user creation (in days)
        EXTRACT(EPOCH FROM (COALESCE(GREATEST(ups.LastPostDate, uca.LastCommentDate), ups.UserCreationDate) - ups.UserCreationDate)) / (3600 * 24) AS ActiveDaysSinceCreation,
        -- Calculate the reputation density per active day (NULL logic)
        CAST(ups.Reputation AS NUMERIC) / NULLIF(EXTRACT(EPOCH FROM (COALESCE(GREATEST(ups.LastPostDate, uca.LastCommentDate), ups.UserCreationDate) - ups.UserCreationDate)) / (3600 * 24), 0) AS ReputationPerActiveDay,
        -- Nested subquery: Find the average number of edits per post for this user's questions
        (
            SELECT COALESCE(AVG(plcm_sub.TotalPostEditEvents), 0.0)
            FROM PostLifeCycleMetrics AS plcm_sub
            WHERE plcm_sub.OwnerUserId = ups.UserId AND plcm_sub.TotalPostEditEvents > 0
        ) AS AvgEditsPerQuestion,
        -- Window function: Rank users by reputation within those active for at least a year
        RANK() OVER (ORDER BY ups.Reputation DESC, ups.TotalPosts DESC, ups.TotalEditsMade DESC) AS GlobalInfluenceRank
    FROM UserPostStats AS ups
    LEFT JOIN UserCommentActivity AS uca ON ups.UserId = uca.UserId
    LEFT JOIN UserBadgeSummary AS ubs ON ups.UserId = ubs.UserId
    LEFT JOIN UserTagProficiency AS utp ON ups.UserId = utp.UserId AND utp.TagRank = 1
    WHERE ups.TotalPosts > 0 OR uca.TotalComments > 0 -- Only consider users with some activity
),
InfluentialCommunityMembers AS (
    -- Identifies highly influential members based on reputation, badges, and positive contributions.
    SELECT
        ucd.UserId,
        ucd.DisplayName,
        ucd.Reputation,
        ucd.GoldBadges,
        ucd.TotalPosts,
        ucd.TotalComments,
        ucd.AvgPostScore,
        ucd.MostProficientTag,
        ucd.ReputationPerActiveDay,
        ucd.UserProfileViews,
        'Influential Contributor' AS UserCategory,
        -- String expression with conditional concatenation
        ucd.DisplayName || ' (Gold Badges: ' || ucd.GoldBadges || COALESCE(', Top Tag: ' || ucd.MostProficientTag, '') || ')' AS UserDescription
    FROM UserConsolidatedData AS ucd
    WHERE
        ucd.Reputation >= 20000
        AND ucd.GoldBadges >= 5
        AND ucd.TotalQuestions >= 50
        AND ucd.AvgPostScore >= 10
        AND ucd.TotalEditsMade >= 100
        AND ucd.AvgEditsPerQuestion >= 2.0 -- Actively maintaining their questions
        AND ucd.ReputationFromAcceptedAnswers >= 150 -- Significant impact via answers
),
PotentialOutliersAndFlaggedUsers AS (
    -- Identifies users with potentially controversial or outlier activity, like high comments but low scores, or posts with duplicate flags.
    SELECT
        ucd.UserId,
        ucd.DisplayName,
        ucd.Reputation,
        ucd.GoldBadges,
        ucd.TotalPosts,
        ucd.TotalComments,
        ucd.AvgPostScore,
        ucd.MostProficientTag,
        ucd.ReputationPerActiveDay,
        ucd.UserProfileViews,
        'Activity Outlier / Flagged' AS UserCategory,
        ucd.DisplayName || ' (Comments: ' || ucd.TotalComments || ', Avg Score: ' || ROUND(ucd.AvgCommentScore::numeric, 2) || ')' AS UserDescription
    FROM UserConsolidatedData AS ucd
    WHERE
        ucd.Reputation < 5000 -- Lower reputation range
        AND ucd.ActiveDaysSinceCreation > 365 -- Active for over a year
        AND (ucd.TotalComments >= 500 AND ucd.AvgCommentScore < 0.5) -- High comment volume but low quality
        AND NOT EXISTS (SELECT 1 FROM Badges AS b WHERE b.UserId = ucd.UserId AND b.TagBased = TRUE) -- No tag-based badges
        -- Correlated subquery in WHERE clause: check if the user has any performance-related questions that are also duplicates.
        AND EXISTS (
            SELECT 1
            FROM PostLifeCycleMetrics AS plcm_inner
            WHERE plcm_inner.OwnerUserId = ucd.UserId
              AND plcm_inner.HasDuplicateLink = TRUE
              AND plcm_inner.PerformanceRelatedContent = TRUE
              AND plcm_inner.PostAgeInDays > 365
            LIMIT 1
        )
)
-- Final result set combining influential members and potential outliers, ordered by influence and category.
SELECT
    icm.UserId,
    icm.DisplayName,
    icm.Reputation,
    icm.UserCategory,
    icm.GoldBadges,
    icm.TotalPosts,
    icm.TotalComments,
    ROUND(icm.AvgPostScore::numeric, 2) AS AvgPostScore,
    icm.MostProficientTag,
    icm.ReputationPerActiveDay,
    icm.UserProfileViews,
    icm.UserDescription,
    -- Complex NULL handling and type casting for a final display value
    COALESCE(
        NULLIF(icm.ReputationPerActiveDay, 0), -- Use NULLIF to handle division by zero or zero values resulting from calculation
        CAST(icm.Reputation AS NUMERIC) / NULLIF(icm.TotalPosts, 0) -- Fallback calculation
    ) AS FinalEngagementMetric
FROM InfluentialCommunityMembers AS icm

UNION ALL

SELECT
    poaf.UserId,
    poaf.DisplayName,
    poaf.Reputation,
    poaf.UserCategory,
    poaf.GoldBadges,
    poaf.TotalPosts,
    poaf.TotalComments,
    ROUND(poaf.AvgPostScore::numeric, 2) AS AvgPostScore,
    poaf.MostProficientTag,
    poaf.ReputationPerActiveDay,
    poaf.UserProfileViews,
    poaf.UserDescription,
    COALESCE(
        NULLIF(poaf.ReputationPerActiveDay, 0),
        CAST(poaf.Reputation AS NUMERIC) / NULLIF(poaf.TotalPosts, 0)
    ) AS FinalEngagementMetric
FROM PotentialOutliersAndFlaggedUsers AS poaf
WHERE poaf.UserId NOT IN (SELECT UserId FROM InfluentialCommunityMembers) -- Ensure no overlap with the influential set

ORDER BY Reputation DESC, UserCategory, DisplayName
LIMIT 200;
