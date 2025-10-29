-- {"query": "1265.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3563} 

WITH UserPostStats AS (
    -- Aggregates various post-related statistics for each user.
    -- Focuses on recent posts to reflect current activity trends.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer') THEN p.Id END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer') THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer') THEN p.Score END) AS AvgAnswerScore,
        SUM(p.ViewCount) AS TotalPostViews,
        SUM(p.CommentCount) AS TotalPostComments,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') THEN p.AcceptedAnswerId END) AS QuestionsWithAcceptedAnswers,
        -- Calculate the "freshness" of the user's last post activity in days.
        EXTRACT(EPOCH FROM (NOW() - MAX(p.LastActivityDate))) / (60 * 60 * 24) AS DaysSinceLastPostActivity,
        -- Window function: Calculate the moving average of scores for a user's answers over time
        AVG(CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer') THEN p.Score ELSE NULL END)
            OVER (PARTITION BY u.Id ORDER BY p.CreationDate ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS MovingAvgAnswerScore
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CommunityOwnedDate IS NULL -- Exclude posts that are community wiki.
      AND p.CreationDate >= NOW() - INTERVAL '5 year' -- Consider posts from the last 5 years.
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10 -- Only include users with more than 10 posts.
),
UserVoteSummary AS (
    -- Summarizes all votes received by a user across all their posts.
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(v.Id) AS TotalVotesReceived,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS TotalUpVotesReceived,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS TotalDownVotesReceived,
        SUM(CASE WHEN vt.Name = 'Favorite' AND v.UserId IS NOT NULL THEN 1 ELSE 0 END) AS TotalFavoritesReceived -- Favorites are cast by other users.
    FROM Posts p
    INNER JOIN Votes v ON p.Id = v.PostId
    INNER JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE p.OwnerUserId IS NOT NULL
      AND v.CreationDate >= NOW() - INTERVAL '5 year'
    GROUP BY p.OwnerUserId
),
UserBadgeAwards AS (
    -- Counts the number of badges, categorized by class, for each user.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    WHERE b.Date >= NOW() - INTERVAL '5 year'
    GROUP BY b.UserId
),
PostTagAnalysis AS (
    -- Extracts and tokenizes tags from question posts for further analysis.
    -- Uses string manipulation and unnesting to handle the tag format.
    SELECT
        p.Id AS PostId,
        p.CreationDate,
        p.ViewCount,
        p.OwnerUserId,
        NULLIF(TRIM(unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))), '') AS TagName
    FROM Posts p
    WHERE p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
      AND p.Tags IS NOT NULL AND p.Tags != ''
      AND p.CreationDate >= NOW() - INTERVAL '3 year' -- Focus on recent tag activity.
),
HotTagsRaw AS (
    -- Calculates preliminary "hotness" metrics for tags.
    SELECT
        TagName,
        SUM(ViewCount) AS TagTotalViews,
        COUNT(DISTINCT PostId) AS TagQuestionCount,
        AVG(EXTRACT(EPOCH FROM (NOW() - CreationDate))) AS AvgTagAgeSeconds
    FROM PostTagAnalysis
    WHERE TagName IS NOT NULL
    GROUP BY TagName
    HAVING COUNT(DISTINCT PostId) > 50 -- Only consider tags with substantial question counts.
),
HotTags AS (
    -- Filters and ranks tags to identify "hot" topics based on combined criteria.
    SELECT
        TagName,
        TagTotalViews,
        TagQuestionCount,
        AvgTagAgeSeconds / (60 * 60 * 24) AS AvgTagAgeDays,
        RANK() OVER (ORDER BY TagTotalViews DESC, TagQuestionCount DESC) AS HotTagRank
    FROM HotTagsRaw
    WHERE (TagTotalViews > 100000 AND TagQuestionCount > 200) -- High view count and many questions
       OR (AvgTagAgeSeconds / (60 * 60 * 24) < 365 AND TagTotalViews > 50000) -- Newer tags with still high views
    ORDER BY HotTagRank
    LIMIT 200 -- Select only the top 200 hottest tags.
),
UserPostHistoryMetrics AS (
    -- Analyzes user's post history for editing frequency, lifecycle events, and migrations.
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (SELECT Id FROM PostHistoryTypes WHERE Name LIKE '%Edit%') THEN 1 ELSE 0 END) AS EditCount, -- Count all edit types.
        SUM(CASE WHEN ph.PostHistoryTypeId IN (SELECT Id FROM PostHistoryTypes WHERE Name IN ('Post Closed', 'Post Reopened', 'Post Deleted', 'Post Undeleted')) THEN 1 ELSE 0 END) AS LifecycleEventCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (SELECT Id FROM PostHistoryTypes WHERE Name LIKE 'Post Migrated %') THEN 1 ELSE 0 END) AS MigrationEventCount,
        -- Calculate the average time (in days) between a user's consecutive edits on *any* of their posts.
        AVG(CASE WHEN ph.PostHistoryTypeId IN (SELECT Id FROM PostHistoryTypes WHERE Name LIKE '%Edit%') THEN
            EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate))) / (60 * 60 * 24)
            ELSE NULL END) AS AvgDaysBetweenEdits
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
      AND ph.CreationDate >= NOW() - INTERVAL '4 year'
    GROUP BY ph.UserId
),
AggregatedCommentScores AS (
    -- Separately aggregates comment scores for comments made by a user on their own posts
    -- and comments made by a user on other users' posts.
    SELECT
        c.UserId,
        SUM(c.Score) AS ScoreOnOwnPosts,
        NULL AS ScoreOnOtherPosts
    FROM Comments c
    JOIN Posts p ON c.PostId = p.Id
    WHERE c.UserId IS NOT NULL AND p.OwnerUserId IS NOT NULL AND c.UserId = p.OwnerUserId
    GROUP BY c.UserId
    UNION ALL
    SELECT
        c.UserId,
        NULL AS ScoreOnOwnPosts,
        SUM(c.Score) AS ScoreOnOtherPosts
    FROM Comments c
    LEFT JOIN Posts p ON c.PostId = p.Id -- LEFT JOIN to include comments on community posts (OwnerUserId IS NULL)
    WHERE c.UserId IS NOT NULL AND (p.OwnerUserId IS NULL OR c.UserId != p.OwnerUserId)
    GROUP BY c.UserId
),
CombinedCommentScores AS (
    -- Combines the two types of comment scores for each user.
    SELECT
        UserId,
        COALESCE(SUM(ScoreOnOwnPosts), 0) AS TotalCommentScoreOnOwnPosts,
        COALESCE(SUM(ScoreOnOtherPosts), 0) AS TotalCommentScoreOnOtherPosts
    FROM AggregatedCommentScores
    GROUP BY UserId
),
UserHotTagParticipation AS (
    -- Identifies users who have contributed to "hot" tags, using a correlated subquery
    -- to count their posts specifically within hot topics.
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT pta.TagName) AS UniqueHotTagInterests,
        -- Correlated subquery: count posts by the user that are associated with any hot tag.
        (SELECT COUNT(DISTINCT p_inner.Id)
         FROM Posts p_inner
         JOIN PostTagAnalysis pta_inner ON p_inner.Id = pta_inner.PostId
         WHERE p_inner.OwnerUserId = u.Id
           AND pta_inner.TagName IN (SELECT TagName FROM HotTags)
        ) AS UserPostsInHotTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostTagAnalysis pta ON p.Id = pta.PostId
    LEFT JOIN HotTags ht ON pta.TagName = ht.TagName
    WHERE u.Id IS NOT NULL -- Ensure we only count for actual users.
    GROUP BY u.Id
)
-- Main query to synthesize all user performance and engagement metrics.
SELECT
    u.Id AS UserIdentifier,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COALESCE(ups.TotalPosts, 0) AS UserTotalPosts,
    COALESCE(ups.TotalAnswers, 0) AS UserTotalAnswers,
    COALESCE(uvs.TotalUpVotesReceived, 0) AS UserTotalUpVotes,
    COALESCE(uba.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(uhpm.EditCount, 0) AS UserTotalEdits,
    COALESCE(uhpm.MigrationEventCount, 0) AS UserMigrationContributions,
    COALESCE(uhtp.UniqueHotTagInterests, 0) AS UserUniqueHotTagInterests,
    COALESCE(uhtp.UserPostsInHotTags, 0) AS UserPostsInHotTags,
    COALESCE(ccs.TotalCommentScoreOnOwnPosts, 0) AS CommentScoreOnOwnPosts,
    COALESCE(ccs.TotalCommentScoreOnOtherPosts, 0) AS CommentScoreOnOtherPosts,
    -- Elaborate calculation: Answer Quality Score (ratio of upvotes to total contributions, scaled by average answer score)
    -- NULLIF is used to prevent division by zero for users with no posts.
    CAST(COALESCE(uvs.TotalUpVotesReceived, 0) AS NUMERIC) / NULLIF(COALESCE(ups.TotalAnswers, 0) + COALESCE(ups.TotalQuestions, 0), 0)
        * (1 + COALESCE(ups.AvgAnswerScore, 0) / 10.0) AS AnswerContributionQualityScore,
    -- Complex calculation: Engagement Factor (combines views, comments, inverse of days since last activity)
    (COALESCE(ups.TotalPostViews, 0) * 0.05 + COALESCE(ups.TotalPostComments, 0) * 0.5)
        / (1 + COALESCE(ups.DaysSinceLastPostActivity, 365) / 60.0) AS EngagementFactor, -- Scale days since last activity to make it less impactful for very old activity.
    -- Composite Score for ranking: a weighted sum of various performance indicators.
    (
        u.Reputation * 0.01 + -- Reputation has a base impact
        COALESCE(uvs.TotalUpVotesReceived, 0) * 0.1 +
        COALESCE(uba.GoldBadges, 0) * 5 +
        COALESCE(uhpm.EditCount, 0) * 0.05 +
        COALESCE(uhpm.MigrationEventCount, 0) * 2.5 +
        COALESCE(uhtp.UserPostsInHotTags, 0) * 0.1 +
        COALESCE(ccs.TotalCommentScoreOnOwnPosts, 0) * 0.15 +
        COALESCE(ccs.TotalCommentScoreOnOtherPosts, 0) * 0.05 +
        (CASE WHEN COALESCE(ups.AvgAnswerScore, 0) > 0 THEN ups.AvgAnswerScore ELSE 0 END) * 0.25
    ) AS CompositeRankingScore,
    -- Window function: Rank users globally based on their CompositeRankingScore.
    RANK() OVER (ORDER BY (
        u.Reputation * 0.01 +
        COALESCE(uvs.TotalUpVotesReceived, 0) * 0.1 +
        COALESCE(uba.GoldBadges, 0) * 5 +
        COALESCE(uhpm.EditCount, 0) * 0.05 +
        COALESCE(uhpm.MigrationEventCount, 0) * 2.5 +
        COALESCE(uhtp.UserPostsInHotTags, 0) * 0.1 +
        COALESCE(ccs.TotalCommentScoreOnOwnPosts, 0) * 0.15 +
        COALESCE(ccs.TotalCommentScoreOnOtherPosts, 0) * 0.05 +
        (CASE WHEN COALESCE(ups.AvgAnswerScore, 0) > 0 THEN ups.AvgAnswerScore ELSE 0 END) * 0.25
    ) DESC) AS UserRankByCompositeScore,
    -- Window function: Categorize users into quartiles based on their Reputation.
    NTILE(4) OVER (ORDER BY u.Reputation DESC) AS ReputationQuartile
FROM Users u
LEFT JOIN UserPostStats ups ON u.Id = ups.UserId
LEFT JOIN UserVoteSummary uvs ON u.Id = uvs.UserId
LEFT JOIN UserBadgeAwards uba ON u.Id = uba.UserId
LEFT JOIN UserPostHistoryMetrics uhpm ON u.Id = uhpm.UserId
LEFT JOIN UserHotTagParticipation uhtp ON u.Id = uhtp.UserId
LEFT JOIN CombinedCommentScores ccs ON u.Id = ccs.UserId
WHERE u.Reputation > 500 -- Filter for users with a significant reputation.
  AND u.CreationDate >= NOW() - INTERVAL '10 year' -- Consider users created within the last 10 years.
ORDER BY CompositeRankingScore DESC, u.Reputation DESC
LIMIT 200; -- Retrieve the top 200 users based on the comprehensive ranking.
