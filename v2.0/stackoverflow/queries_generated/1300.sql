-- {"query": "1300.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3431} 

WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(b.Date) AS LatestBadgeDate,
        -- Correlated subquery to check if the user has a Gold badge
        EXISTS (
            SELECT 1
            FROM Badges gold_b
            WHERE gold_b.UserId = u.Id AND gold_b.Class = 1
        ) AS HasGoldBadge,
        -- Calculate average comment length for user's comments
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        -- User engagement score calculation: weighted sum of reputation, posts, comments, and post scores
        (u.Reputation * 0.5) + (COUNT(DISTINCT p.Id) * 0.2) + (COUNT(DISTINCT c.Id) * 0.1) + (COALESCE(SUM(p.Score), 0) * 0.2) AS UserEngagementScore
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostHistoricalMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastEditDate,
        p.LastActivityDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        p.ClosedDate,
        -- Calculate the time difference in hours between the first and last recorded edit event
        EXTRACT(EPOCH FROM (MAX(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.CreationDate ELSE NULL END) - MIN(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.CreationDate ELSE NULL END))) / 3600 AS HoursBetweenFirstAndLastEdit,
        -- Count distinct editors for a post based on PostHistory entries
        COUNT(DISTINCT ph.UserId) AS DistinctEditorCount,
        -- Determine if the post has ever been explicitly reopened after being closed
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        -- Determine if the post was ever involved in a migration
        MAX(CASE WHEN ph.PostHistoryTypeId IN (17, 35, 36) THEN 1 ELSE 0 END) AS WasMigrated,
        -- Average length of comments directly on this post
        AVG(LENGTH(pc.Text)) AS AvgPostCommentLength,
        -- Categorize post popularity based on view count and score (primarily for questions)
        CASE
            WHEN p.PostTypeId = 1 AND p.ViewCount > 5000 AND p.Score > 50 THEN 'Hot'
            WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 AND p.Score > 10 THEN 'Warm'
            ELSE 'Normal'
        END AS PostPopularityCategory
    FROM
        Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Comments pc ON p.Id = pc.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastEditDate, p.LastActivityDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.AcceptedAnswerId, p.ClosedDate
),
QuestionTagAnalysis AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        -- Use string functions to parse tags from the 'Tags' string column
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 -- Ensure it's a question and has valid tags
),
TagPerformance AS (
    SELECT
        qta.TagName,
        COUNT(DISTINCT qta.QuestionId) AS TotalQuestionsWithTag,
        AVG(pm.PostScore) AS AvgScoreForTag,
        SUM(pm.ViewCount) AS TotalViewsForTag,
        AVG(pm.AnswerCount) AS AvgAnswersForTag,
        -- Window function: Rank tags by their average score
        RANK() OVER (ORDER BY AVG(pm.PostScore) DESC NULLS LAST) AS TagScoreRank
    FROM
        QuestionTagAnalysis qta
    JOIN PostHistoricalMetrics pm ON qta.QuestionId = pm.PostId
    GROUP BY
        qta.TagName
),
UserPostInteraction AS (
    SELECT
        p.OwnerUserId AS UserId,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score AS PostScore,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        -- Window function: Calculate average score of user's posts created in the same month
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId, DATE_TRUNC('month', p.CreationDate)) AS AvgMonthlyUserPostScore,
        -- Window function: Calculate the score difference from the previous post by the same user
        p.Score - LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS ScoreChangeFromPreviousPost,
        -- Correlated subquery: Check if this specific post has a linked duplicate
        EXISTS (
            SELECT 1
            FROM PostLinks pl_inner
            WHERE pl_inner.PostId = p.Id AND pl_inner.LinkTypeId = 3 -- LinkTypeId = 3 indicates a duplicate link
        ) AS HasDuplicateLink,
        -- Correlated subquery: Calculate the average score of answers to this question if it is a question
        CASE WHEN p.PostTypeId = 1 THEN (
            SELECT AVG(ans.Score)
            FROM Posts ans
            WHERE ans.ParentId = p.Id AND ans.PostTypeId = 2
        ) ELSE NULL END AS AvgAnswerScoreForQuestion
    FROM
        Posts p
    WHERE p.OwnerUserId IS NOT NULL
)
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.UserCreationDate,
    ues.LastAccessDate,
    ues.TotalPosts,
    ues.TotalQuestions,
    ues.TotalAnswers,
    ues.TotalPostScore,
    ues.TotalBadges,
    ues.HasGoldBadge,
    ues.UserEngagementScore,
    -- Window function: Rank users by their engagement score within users created in the same year
    RANK() OVER (PARTITION BY EXTRACT(YEAR FROM ues.UserCreationDate) ORDER BY ues.UserEngagementScore DESC) AS UserEngagementRankByCreationYear,
    -- Window function: Calculate the average reputation of users in the same geographical location
    AVG(ues.Reputation) OVER (PARTITION BY u.Location) AS AvgReputationInLocation,
    -- Calculated ratio: Percentage of a user's total posts that are answers
    CAST(ues.TotalAnswers AS NUMERIC) / NULLIF(ues.TotalPosts, 0) AS AnswerPostRatio,
    -- Calculated average: Overall average view count for questions authored by this user
    CAST(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS NUMERIC) / NULLIF(COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END), 0) AS AvgQuestionViewsByUser,
    -- String expression: Extract the domain from the user's website URL
    SUBSTRING(u.WebsiteUrl FROM '://([^/]+)') AS WebsiteDomain,
    -- NULL logic: Provide a default string if the user's location is NULL
    COALESCE(u.Location, 'Unknown Location') AS UserLocation,

    -- Aggregated post-level metrics for the user:
    COUNT(CASE WHEN pm.PostPopularityCategory = 'Hot' THEN 1 END) AS HotPostsCount,
    COUNT(CASE WHEN pm.PostPopularityCategory = 'Warm' THEN 1 END) AS WarmPostsCount,
    AVG(pm.DistinctEditorCount) AS AvgDistinctEditorCountAcrossPosts,
    AVG(pm.HoursBetweenFirstAndLastEdit) AS AvgPostEditDurationHours,
    MAX(upi.AvgMonthlyUserPostScore) AS MaxAvgMonthlyPostScore,
    MAX(upi.ScoreChangeFromPreviousPost) AS MaxScoreChangeFromPrevPost,
    BOOL_OR(upi.HasDuplicateLink) AS HasUserPostsWithDuplicates, -- Boolean aggregation: TRUE if any of user's posts have a duplicate link
    AVG(upi.AvgAnswerScoreForQuestion) AS AvgAnswerScoreForUserQuestions,

    -- Non-correlated subquery: Overall average positive post score across the entire database
    (SELECT AVG(Score) FROM Posts WHERE Score IS NOT NULL AND Score > 0) AS OverallAvgPositivePostScore,

    -- Correlated subquery: Find the tag with the highest average score among those used by the user
    (SELECT tp_inner.TagName
     FROM QuestionTagAnalysis qta_inner
     JOIN TagPerformance tp_inner ON qta_inner.TagName = tp_inner.TagName
     WHERE qta_inner.OwnerUserId = u.Id
     ORDER BY tp_inner.AvgScoreForTag DESC NULLS LAST
     LIMIT 1) AS TopPerformingTag,
    -- Correlated subquery: Get the average score for the top-performing tag of the user
    (SELECT tp_inner.AvgScoreForTag
     FROM QuestionTagAnalysis qta_inner
     JOIN TagPerformance tp_inner ON qta_inner.TagName = tp_inner.TagName
     WHERE qta_inner.OwnerUserId = u.Id
     ORDER BY tp_inner.AvgScoreForTag DESC NULLS LAST
     LIMIT 1) AS TopPerformingTagAvgScore,

    -- Complicated predicate/expression: Identify "High Engagement Experienced Developers" based on DisplayName, creation year, and post count
    CASE
        WHEN LOWER(ues.DisplayName) LIKE '%dev%' OR LOWER(ues.DisplayName) LIKE '%prog%'
             AND EXTRACT(YEAR FROM ues.UserCreationDate) >= 2010
             AND ues.TotalPosts > 50
        THEN TRUE
        ELSE FALSE
    END AS IsHighEngagementExperiencedDeveloper,

    -- Nested/Complex Calculation: Ratio of questions owned by this user that have an accepted answer to total questions with answers
    CAST(SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS NUMERIC)
    / NULLIF(SUM(CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.AnswerCount ELSE 0 END), 0)
    AS UserAcceptedAnswerRatio,

    -- Time since last activity of the user's most recent post, in days
    EXTRACT(DAY FROM (NOW() - MAX(upi.LastActivityDate))) AS DaysSinceLastUserPostActivity,

    -- String comparison and NULL handling: Categorize user's 'AboutMe' section content
    CASE WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100 AND u.AboutMe ILIKE '%sql%'
         THEN 'SQL Enthusiast with Detailed Profile'
         WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 0
         THEN 'User with Basic Profile'
         ELSE 'No AboutMe Description'
    END AS AboutMeStatus,

    -- Aggregate count of posts owned by the user that were closed for a specific reason (e.g., 'Duplicate', assuming '101' is the ID)
    SUM(CASE WHEN ph_closed.PostHistoryTypeId = 10 AND ph_closed.Comment = '101' THEN 1 ELSE 0 END) AS TotalDuplicateClosuresOnOwnedPosts,

    -- Count distinct posts by others that link to any of this user's posts
    COUNT(DISTINCT pl_linked.PostId) AS TotalLinkedPostsByOthers,
    -- Count distinct posts owned by this user that are marked as duplicates of other posts
    COUNT(DISTINCT pl_duplicate.RelatedPostId) AS TotalOwnedPostsMarkedAsDuplicates

FROM
    Users u
JOIN UserEngagementSummary ues ON u.Id = ues.UserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN PostHistoricalMetrics pm ON p.Id = pm.PostId
LEFT JOIN UserPostInteraction upi ON u.Id = upi.UserId AND p.Id = upi.PostId -- Join upi directly to p for post-level metrics

LEFT JOIN PostHistory ph_closed ON p.Id = ph_closed.PostId AND ph_closed.PostHistoryTypeId = 10 -- Only Post Closed events
LEFT JOIN PostLinks pl_linked ON p.Id = pl_linked.RelatedPostId AND pl_linked.LinkTypeId = 1 -- 'Linked' type, where user's post is the target
LEFT JOIN PostLinks pl_duplicate ON p.Id = pl_duplicate.PostId AND pl_duplicate.LinkTypeId = 3 -- 'Duplicate' type, where user's post is the source (i.e., this post IS a duplicate)

GROUP BY
    ues.UserId, ues.DisplayName, ues.Reputation, ues.UserCreationDate, ues.LastAccessDate, ues.TotalPosts, ues.TotalQuestions,
    ues.TotalAnswers, ues.TotalPostScore, ues.TotalBadges, ues.HasGoldBadge, ues.UserEngagementScore, u.Location, u.WebsiteUrl,
    u.AboutMe
ORDER BY
    ues.UserEngagementScore DESC, ues.Reputation DESC
LIMIT 100;
