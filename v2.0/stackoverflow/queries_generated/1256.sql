-- {"query": "1256.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4078} 

WITH UserActivitySummary AS (
    -- Calculates comprehensive activity metrics for each user, including post counts, scores, comment counts,
    -- votes received on their posts, and badge counts. Uses LEFT JOINs to ensure all users are included.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        COALESCE(COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1), 0) AS TotalQuestions,
        COALESCE(COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2), 0) AS TotalAnswers,
        COALESCE(COUNT(DISTINCT p.Id), 0) AS TotalPosts,
        COALESCE(SUM(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)), 0) AS TotalPostScore,
        COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)), 0.0) AS AvgPostScore,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.CreationDate) AS LastPostDate,
        COALESCE(COUNT(DISTINCT c.Id), 0) AS TotalCommentsMade,
        -- Aggregating votes received on posts owned by the user
        COALESCE(SUM(CASE WHEN pv.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpVotesReceived,
        COALESCE(SUM(CASE WHEN pv.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownVotesReceived,
        -- Aggregating badge counts by class
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes pv ON p.Id = pv.PostId AND pv.VoteTypeId IN (2, 3) -- Only UpMod and DownMod votes on owned posts
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
),
PostEngagementDetails AS (
    -- Gathers detailed engagement metrics for questions, including total votes, distinct editors,
    -- and uses correlated subqueries for accepted answer owner reputation and high-scoring answers.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        p.ClosedDate,
        (p.ClosedDate IS NOT NULL) AS IsClosed,
        EXTRACT(DAY FROM NOW() - p.LastActivityDate) AS DaysSinceLastActivity,
        -- Total votes on post, excluding specific user-action types like Favorite or Bounty votes
        COALESCE(SUM(CASE WHEN v.VoteTypeId IN (2, 3, 4, 10, 11, 12, 16) THEN 1 ELSE 0 END), 0) AS TotalVotesOnPost,
        COALESCE(COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.UserId IS NOT NULL), 0) AS DistinctEditorsCount,
        -- Correlated subquery: Fetches the reputation of the user who provided the accepted answer
        (SELECT COALESCE(u_ans.Reputation, 0)
         FROM Posts ans
         JOIN Users u_ans ON ans.OwnerUserId = u_ans.Id
         WHERE ans.Id = p.AcceptedAnswerId AND p.AcceptedAnswerId IS NOT NULL
        ) AS AcceptedAnswerOwnerReputation,
        -- Correlated subquery: Checks if any answer to this question has a high score AND was provided by an editor of the question
        (SELECT EXISTS (
            SELECT 1
            FROM Posts ans_high
            WHERE ans_high.ParentId = p.Id
            AND ans_high.Score > 50
            AND ans_high.OwnerUserId IN (
                SELECT DISTINCT ph_inner.UserId
                FROM PostHistory ph_inner
                WHERE ph_inner.PostId = p.Id AND ph_inner.PostHistoryTypeId IN (4, 5, 6) -- Editor post history types
            )
        )) AS HasHighScoringAnswerByEditor
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId NOT IN (1, 5, 6, 7, 8, 9, 14, 15)
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE p.PostTypeId = 1 -- Focus exclusively on questions
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount,
        p.CommentCount, p.FavoriteCount, p.LastActivityDate, p.ClosedDate, p.AcceptedAnswerId
),
TagPostAggregates AS (
    -- Parses the 'Tags' string from posts and creates a row for each tag associated with a question.
    -- This CTE is crucial for tag-based analysis.
    SELECT
        unnest(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) AS TagName,
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score AS PostScore,
        p.CreationDate AS PostCreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 -- Ensure tags are present and valid
),
TagSummary AS (
    -- Aggregates statistics per tag, including total questions, average score, distinct contributors,
    -- and counts of tag-based badges.
    SELECT
        tpa.TagName,
        COUNT(DISTINCT tpa.PostId) AS TotalQuestionsTagged,
        COALESCE(AVG(tpa.PostScore), 0.0) AS AvgQuestionScoreForTag,
        COUNT(DISTINCT tpa.OwnerUserId) AS DistinctUsersContributingToTag,
        COALESCE(SUM(CASE WHEN b.Class = 1 AND b.TagBased = TRUE THEN 1 ELSE 0 END), 0) AS GoldTagBadgesCount,
        COALESCE(SUM(CASE WHEN b.Class = 2 AND b.TagBased = TRUE THEN 1 ELSE 0 END), 0) AS SilverTagBadgesCount,
        COALESCE(SUM(CASE WHEN b.Class = 3 AND b.TagBased = TRUE THEN 1 ELSE 0 END), 0) AS BronzeTagBadgesCount,
        t.Count AS GlobalTagCount,
        MAX(tpa.PostCreationDate) AS LastPostInTagDate
    FROM TagPostAggregates tpa
    LEFT JOIN Badges b ON tpa.OwnerUserId = b.UserId AND b.TagBased = TRUE AND b.Name = tpa.TagName
    JOIN Tags t ON tpa.TagName = t.TagName
    GROUP BY tpa.TagName, t.Count
),
TopPostersPerTag AS (
    -- Identifies and ranks users within each tag based on their total post score and question count in that tag.
    -- Uses a window function (RANK) partitioned by TagName.
    SELECT
        tpa.OwnerUserId AS UserId,
        tpa.TagName,
        SUM(tpa.PostScore) AS TagSpecificScore,
        COUNT(DISTINCT tpa.PostId) AS TagSpecificQuestionCount,
        RANK() OVER (PARTITION BY tpa.TagName ORDER BY SUM(tpa.PostScore) DESC, COUNT(DISTINCT tpa.PostId) DESC) AS RankInTag
    FROM TagPostAggregates tpa
    GROUP BY tpa.OwnerUserId, tpa.TagName
    HAVING COUNT(DISTINCT tpa.PostId) >= 3 AND SUM(tpa.PostScore) > 10
),
RecentHighlyViewedPosts AS (
    -- Filters for questions that are recent (last 6 months), highly viewed, and have a good score.
    -- Uses a DENSE_RANK window function to rank them.
    SELECT
        ped.PostId,
        ped.OwnerUserId,
        ped.PostCreationDate,
        ped.ViewCount,
        ped.Score,
        ped.DaysSinceLastActivity,
        DENSE_RANK() OVER (ORDER BY ped.ViewCount DESC, ped.Score DESC) AS ViewScoreRank
    FROM PostEngagementDetails ped
    WHERE ped.PostCreationDate > NOW() - INTERVAL '6 months'
      AND ped.ViewCount >= 5000
      AND ped.Score >= 10
),
UsersWithHighEngagementAndRecentActivity AS (
    -- Selects users who are active and have a decent reputation, calculating their engagement ratio
    -- and ranking them. Includes a window function for average reputation in the same location.
    SELECT
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalQuestions,
        uas.AvgPostScore,
        uas.GoldBadges,
        uas.SilverBadges,
        uas.BronzeBadges,
        -- Window function: Average reputation of users in the same location
        AVG(u.Reputation) OVER (PARTITION BY u.Location) AS AvgReputationInLocation,
        -- Window function: Rank users by their total upvotes received
        RANK() OVER (ORDER BY uas.TotalUpVotesReceived DESC, uas.TotalPosts DESC) AS UpvoteReceiverRank,
        -- Complex calculation: Engagement ratio (upvotes received / total comments made + posts)
        CASE
            WHEN (uas.TotalCommentsMade + uas.TotalPosts) = 0 THEN 0.0
            ELSE CAST(uas.TotalUpVotesReceived AS NUMERIC) / (uas.TotalCommentsMade + uas.TotalPosts)
        END AS EngagementRatio
    FROM UserActivitySummary uas
    JOIN Users u ON uas.UserId = u.Id
    WHERE uas.Reputation >= 1000
      AND uas.TotalPosts >= 10
      AND uas.LastPostDate IS NOT NULL
      AND uas.LastPostDate > NOW() - INTERVAL '2 years'
),
UserQuestionCumulativeViews AS (
    -- Calculates the cumulative sum of view counts for each question posted by users, ordered by post creation date.
    -- This uses a window function with an ORDER BY clause.
    SELECT
        ped.PostId,
        ped.OwnerUserId AS UserId,
        ped.PostCreationDate,
        ped.ViewCount,
        SUM(ped.ViewCount) OVER (PARTITION BY ped.OwnerUserId ORDER BY ped.PostCreationDate) AS CumulativeQuestionViewsAtPostDate
    FROM PostEngagementDetails ped
    WHERE ped.OwnerUserId IN (SELECT UserId FROM UsersWithHighEngagementAndRecentActivity) -- Pre-filter for relevant users
)
-- Main Query: Joins all CTEs to provide a comprehensive analysis of highly engaged users,
-- their contribution to popular tags, post performance, and overall impact.
SELECT
    uhr.DisplayName,
    uhr.Reputation,
    -- Complex calculation: Reputation normalized by account age (years)
    uhr.Reputation / COALESCE(NULLIF(CAST(EXTRACT(YEAR FROM AGE(u.CreationDate)) + 1 AS NUMERIC), 0), 1) AS ReputationPerYear,
    uhr.TotalQuestions,
    uhr.AvgPostScore,
    uhr.GoldBadges,
    uhr.SilverBadges,
    uhr.BronzeBadges,
    uhr.UpvoteReceiverRank,
    uhr.EngagementRatio,
    uhr.AvgReputationInLocation,
    -- String expression: Aggregates all popular tags a user has contributed to
    COALESCE(STRING_AGG(DISTINCT ts.TagName, ', ') FILTER (WHERE ts.TagName IS NOT NULL), 'No Popular Tags') AS PopularTagsContributedTo,
    COALESCE(AVG(ts.AvgQuestionScoreForTag) FILTER (WHERE ts.TagName IS NOT NULL), 0.0) AS AvgScoreInPopularTags,
    COALESCE(MAX(ts.DistinctUsersContributingToTag) FILTER (WHERE ts.TagName IS NOT NULL), 0) AS MaxContributorsInAnyTag,
    COALESCE(MAX(ts.GoldTagBadgesCount) FILTER (WHERE ts.TagName IS NOT NULL), 0) AS MaxGoldTagBadgesForAnyTag,
    -- Complicated predicate: Checks if the user is a top 5 poster in ANY of their contributed popular tags
    BOOL_OR(tpt.RankInTag <= 5 AND tpt.TagName = ts.TagName) AS IsTop5PosterInAnyPopularTag,
    -- String expression with NULL logic: Concatenates user location and last access date
    COALESCE(u.Location, 'Unknown Location') || ' | ' || TO_CHAR(u.LastAccessDate, 'YYYY-MM-DD HH24:MI') AS UserLocationAndLastAccess,
    -- Correlated subquery: Counts the number of questions owned by the user that are duplicates of other posts
    (SELECT COUNT(DISTINCT pl_dup.RelatedPostId)
     FROM PostLinks pl_dup
     WHERE pl_dup.PostId IN (SELECT p_owner.Id FROM Posts p_owner WHERE p_owner.OwnerUserId = uhr.UserId AND p_owner.PostTypeId = 1)
     AND pl_dup.LinkTypeId = 3
    ) AS DuplicatedQuestionsByOwnerCount,
    -- Non-correlated subquery: Calculates the average score of recent, well-answered questions, excluding the current user's own recent hot posts
    (SELECT COALESCE(AVG(ped_sub.Score), 0.0)
     FROM PostEngagementDetails ped_sub
     WHERE ped_sub.PostCreationDate > NOW() - INTERVAL '6 months'
     AND ped_sub.AnswerCount > 3
     AND ped_sub.PostId NOT IN (SELECT rhvp_sub.PostId FROM RecentHighlyViewedPosts rhvp_sub WHERE rhvp_sub.OwnerUserId = uhr.UserId) -- Set operator (EXCEPT) effect
    ) AS AvgScoreOfActiveQuestionsInCommunity,
    -- Aggregated counts for user's posts meeting specific criteria
    COUNT(DISTINCT ped.PostId) FILTER (WHERE ped.IsClosed) AS TotalClosedQuestions,
    COUNT(DISTINCT ped.PostId) FILTER (WHERE ped.HasHighScoringAnswerByEditor) AS QuestionsWithEditorHighScoreAnswer,
    COALESCE(MAX(ped.DaysSinceLastActivity) FILTER (WHERE ped.PostId IS NOT NULL), 0) AS MaxQuestionDaysSinceActivity,
    -- Retrieves the latest cumulative view count for the user's questions
    COALESCE(MAX(uqcv.CumulativeQuestionViewsAtPostDate) FILTER (WHERE uqcv.PostId IS NOT NULL), 0) AS LatestCumulativeQuestionViews,
    -- Checks if the user has any recent highly viewed posts
    BOOL_OR(rhvp.PostId IS NOT NULL) AS HasRecentHotPost
FROM UsersWithHighEngagementAndRecentActivity uhr
JOIN Users u ON uhr.UserId = u.Id -- Re-join Users for specific columns
LEFT JOIN PostEngagementDetails ped ON uhr.UserId = ped.OwnerUserId
LEFT JOIN TagPostAggregates tpa ON uhr.UserId = tpa.OwnerUserId AND ped.PostId = tpa.PostId -- Link to get individual tags per post
LEFT JOIN TagSummary ts ON tpa.TagName = ts.TagName AND ts.GlobalTagCount > 1000 -- Only consider popular tags
LEFT JOIN TopPostersPerTag tpt ON uhr.UserId = tpt.UserId AND tpt.TagName = ts.TagName
LEFT JOIN RecentHighlyViewedPosts rhvp ON uhr.UserId = rhvp.OwnerUserId
LEFT JOIN UserQuestionCumulativeViews uqcv ON uhr.UserId = uqcv.UserId
WHERE
    uhr.EngagementRatio > 0.05 -- Filter for users with significant interaction
    AND (u.Location IS NOT NULL OR u.WebsiteUrl IS NOT NULL) -- Users must have some identifiable info
    AND (ts.TagName IS NULL OR ts.AvgQuestionScoreForTag > 5) -- Either no popular tag, or popular tag has good average score
GROUP BY
    uhr.DisplayName, uhr.Reputation, u.CreationDate, uhr.TotalQuestions, uhr.AvgPostScore,
    uhr.GoldBadges, uhr.SilverBadges, uhr.BronzeBadges, uhr.UpvoteReceiverRank,
    uhr.EngagementRatio, uhr.AvgReputationInLocation, u.Location, u.LastAccessDate, uhr.UserId
HAVING
    COUNT(DISTINCT ped.PostId) FILTER (WHERE ped.PostId IS NOT NULL) >= 5 -- User must have at least 5 questions matching PED criteria
    AND SUM(ped.Score) FILTER (WHERE ped.PostId IS NOT NULL) > 50 -- Total score of their relevant questions
ORDER BY
    uhr.UpvoteReceiverRank ASC, uhr.Reputation DESC, QuestionsWithEditorHighScoreAnswer DESC
LIMIT 50;
