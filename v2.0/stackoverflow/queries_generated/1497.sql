-- {"query": "1497.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3033} 
WITH UserActivitySummary AS (
    -- Summarizes user activity, including counts of owned posts, comments, votes given, and accepted answers.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        COALESCE(COUNT(DISTINCT p.Id), 0) AS TotalPostsOwned,
        COALESCE(COUNT(DISTINCT c.Id), 0) AS TotalCommentsMade,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 AND v.UserId = u.Id THEN 1 ELSE 0 END), 0) AS TotalUpVotesGiven,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 AND v.UserId = u.Id THEN 1 ELSE 0 END), 0) AS TotalDownVotesGiven,
        COALESCE(SUM(CASE WHEN pa.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END), 0) AS TotalAcceptedAnswers,
        -- Calculate the average reputation of users created in the same month as this user
        AVG(u_other.Reputation) FILTER (WHERE DATE_TRUNC('month', u_other.CreationDate) = DATE_TRUNC('month', u.CreationDate)) OVER (PARTITION BY DATE_TRUNC('month', u.CreationDate)) AS AvgReputationInCreationMonth
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Posts pa ON pa.AcceptedAnswerId = p.Id -- For accepted answers
    LEFT JOIN Users u_other ON TRUE -- For window function over users
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views
),
PostEngagementMetrics AS (
    -- Calculates post-level engagement, including scores, views, and content analysis.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount AS PostCommentCount,
        p.FavoriteCount,
        p.Tags, -- Required for LATERAL JOIN in main query
        p.Body,
        NULLIF(p.ClosedDate, 'infinity') AS ClosedDateAdjusted, -- Handles special 'infinity' date value
        ARRAY_LENGTH(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'), 1) AS TagCount,
        -- Window function: running sum of scores for posts by the same owner, ordered by creation date
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS OwnerRunningPostScore,
        -- Window function: average score for posts of the same type within a 30-day moving window
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate RANGE BETWEEN INTERVAL '15 DAY' PRECEDING AND INTERVAL '15 DAY' FOLLOWING) AS AvgPostScoreTypeWindow,
        -- String expression to check for common code snippets or external links in the body
        (POSITION('<pre>' IN LOWER(p.Body)) > 0 OR POSITION('<code>' IN LOWER(p.Body)) > 0 OR POSITION('<a href=' IN LOWER(p.Body)) > 0) AS HasCodeOrExternalLink,
        -- Complex calculation: hours between post creation and last activity
        EXTRACT(HOUR FROM AGE(p.LastActivityDate, p.CreationDate)) AS HoursUntilLastActivity,
        -- NULL logic for Body content: provide an excerpt or default text
        COALESCE(SUBSTRING(p.Body, 1, 50), '(Empty Body)') AS BodyExcerpt
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
),
PostHistoryEvents AS (
    -- Analyzes post history for specific event types and time differences.
    SELECT
        ph.PostId,
        ph.CreationDate AS HistoryEventDate,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        ph.UserId AS HistoryEditorUserId,
        ph.Comment AS HistoryComment,
        -- Correlated subquery: retrieve the associated User's display name
        (SELECT DisplayName FROM Users WHERE Id = ph.UserId) AS EditorDisplayName,
        -- Window function: time difference to the previous edit/event of the same post in minutes
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) / 60 AS MinsSincePrevHistoryEvent,
        -- Correlated subquery: check if the editor is the original post owner
        (SELECT OwnerUserId FROM Posts WHERE Id = ph.PostId) = ph.UserId AS IsOwnerEditing
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13, 16) -- Edits, Close, Reopen, Delete, Undelete, Community Owned
),
UserBadgeSummary AS (
    -- Summarizes badge information for users, including counts and percentages.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate,
        -- Calculate percentage of tag-based badges, handling division by zero with NULLIF
        ROUND(CAST(SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS NUMERIC) / NULLIF(COUNT(b.Id), 0) * 100, 2) AS PercentTagBasedBadges
    FROM Badges b
    GROUP BY b.UserId
),
TagUsageAggregates AS (
    -- Aggregates global statistics for tags from posts.
    SELECT
        TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))) AS TagName,
        COUNT(DISTINCT p.Id) AS PostsWithThisTag,
        AVG(p.Score) AS AverageScoreForTag,
        MAX(p.ViewCount) AS MaxViewCountForTag
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.Tags != '' AND LENGTH(p.Tags) > 2 -- Exclude empty or malformed tags
    GROUP BY TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')))
),
PostLinkRelationships AS (
    -- Analyzes post link relationships, counting linked posts and duplicates.
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS TotalRelatedPosts,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedFromOtherPosts,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatesOfOtherPosts,
        -- Correlated subquery: count linked posts that are questions
        SUM(CASE WHEN (SELECT PostTypeId FROM Posts WHERE Id = pl.RelatedPostId) = 1 THEN 1 ELSE 0 END) AS LinkedToQuestionsCount,
        -- Correlated subquery: calculate average score of related posts
        (SELECT AVG(Score) FROM Posts WHERE Id IN (SELECT RelatedPostId FROM PostLinks WHERE PostId = pl.PostId)) AS AvgRelatedPostScore
    FROM PostLinks pl
    GROUP BY pl.PostId
)
-- Main query combining results with complex joins, window functions, and conditional logic.
SELECT
    COALESCE(uas.UserId, pem.OwnerUserId, -1) AS FinalUserId, -- NULL logic: Fallback UserId for entries without a direct user match
    COALESCE(uas.DisplayName, 'Community User') AS FinalDisplayName,
    uas.Reputation,
    uas.CreationDate,
    uas.LastAccessDate,
    uas.UserProfileViews,
    uas.TotalPostsOwned,
    uas.TotalCommentsMade,
    uas.TotalUpVotesGiven,
    uas.TotalDownVotesGiven,
    uas.TotalAcceptedAnswers,
    uas.AvgReputationInCreationMonth,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.PercentTagBasedBadges,
    pem.PostId,
    pem.PostTypeName,
    pem.Title,
    pem.PostCreationDate,
    pem.LastActivityDate,
    pem.PostScore,
    pem.ViewCount,
    pem.AnswerCount,
    pem.PostCommentCount,
    pem.FavoriteCount,
    pem.TagCount AS PostTagCount,
    pem.OwnerRunningPostScore,
    pem.AvgPostScoreTypeWindow,
    pem.HasCodeOrExternalLink,
    pem.HoursUntilLastActivity,
    pem.BodyExcerpt,
    ph.HistoryEventDate AS LastHistoryEventDate,
    ph.HistoryTypeName AS LastHistoryEventType,
    ph.MinsSincePrevHistoryEvent,
    ph.IsOwnerEditing,
    plr.TotalRelatedPosts,
    plr.LinkedFromOtherPosts,
    plr.DuplicatesOfOtherPosts,
    plr.LinkedToQuestionsCount,
    plr.AvgRelatedPostScore,
    tga.PostsWithThisTag AS MostDominantTagPostsCount,
    tga.AverageScoreForTag AS MostDominantTagAvgScore,
    -- Complex CASE expression to categorize user engagement level
    CASE
        WHEN COALESCE(uas.Reputation, 0) >= 10000 AND COALESCE(uas.TotalPostsOwned, 0) >= 100 THEN 'LegendaryContributor'
        WHEN COALESCE(uas.Reputation, 0) >= 5000 AND COALESCE(uas.TotalPostsOwned, 0) >= 50 THEN 'HighlyActiveExpert'
        WHEN COALESCE(uas.Reputation, 0) >= 1000 AND COALESCE(uas.TotalPostsOwned, 0) >= 10 THEN 'EstablishedParticipant'
        WHEN COALESCE(uas.Reputation, 0) < 1000 AND COALESCE(uas.TotalPostsOwned, 0) = 0 AND COALESCE(uas.TotalCommentsMade, 0) = 0 THEN 'LurkerOrNewbie'
        ELSE 'RegularUser'
    END AS UserEngagementTier,
    -- Window functions for global and partitioned ranking
    NTILE(10) OVER (ORDER BY COALESCE(uas.Reputation, 0) DESC, COALESCE(uas.TotalPostsOwned, 0) DESC) AS GlobalReputationPostTile,
    RANK() OVER (PARTITION BY pem.PostTypeId ORDER BY COALESCE(pem.PostScore, 0) DESC, COALESCE(pem.ViewCount, 0) DESC) AS RankWithinPostType,
    -- Complicated boolean logic derived from multiple columns
    (pem.ClosedDateAdjusted IS NOT NULL AND pem.HoursUntilLastActivity IS NOT NULL AND pem.HoursUntilLastActivity < 24 * 7) AS ClosedQuicklyAfterLastActivity,
    -- String expressions: format the start of the title, handle potential NULLs
    UPPER(COALESCE(SUBSTRING(pem.Title, 1, 1), '')) || LOWER(COALESCE(SUBSTRING(pem.Title, 2, 20), '')) AS FormattedTitleStart,
    -- NULL logic and complex arithmetic comparison for identifying high rep users with relatively low post scores
    (COALESCE(uas.Reputation, 0) > 0 AND COALESCE(pem.PostScore, 0) > 0 AND uas.Reputation / pem.PostScore > 100) AS HighRepLowPostScoreRatio,
    -- Correlated subquery check: identify posts with comments containing 'duplicate' warnings from other users
    EXISTS (
        SELECT 1
        FROM Comments sc
        WHERE sc.PostId = pem.PostId
        AND sc.Text ILIKE '%[duplicate]%'
        AND sc.UserId IS NOT NULL
        AND sc.UserId != pem.OwnerUserId
    ) AS HasDuplicateWarningComment,
    -- Conditional check for users who have many posts but no badges
    (COALESCE(uas.TotalPostsOwned, 0) > 5 AND ubs.TotalBadges IS NULL) AS BadgeLessHighPoster
FROM
    UserActivitySummary uas
FULL OUTER JOIN PostEngagementMetrics pem ON uas.UserId = pem.OwnerUserId -- FULL OUTER JOIN to capture users without posts