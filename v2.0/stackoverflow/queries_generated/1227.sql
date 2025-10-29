-- {"query": "1227.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3276} 

WITH UserAggregates AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        u.DisplayName,
        u.Location,
        COUNT(DISTINCT p.Id) AS TotalOwnedPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS OwnedQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS OwnedAnswers,
        SUM(p.Score) AS TotalOwnedPostScore,
        SUM(p.ViewCount) AS TotalOwnedPostViews,
        SUM(p.AnswerCount) AS TotalAnswersOnOwnedQuestions,
        SUM(p.FavoriteCount) AS TotalOwnedPostFavorites,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        -- Correlated subquery: retrieve the text of the user's most recent comment, if any
        (
            SELECT cc.Text
            FROM Comments cc
            WHERE cc.UserId = u.Id
            ORDER BY cc.CreationDate DESC
            LIMIT 1
        ) AS LatestCommentTextByUser
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, u.DisplayName, u.Location
),
PostDetailsWithHistory AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.CommentCount AS PostCommentCount,
        -- Complex string expression: use Title, or an excerpt from Body if Title is NULL
        COALESCE(p.Title, LEFT(p.Body, 100) || '...') AS PostTitleOrExcerpt,
        -- String expression: parse tags into an array, handling potential NULL or empty tags
        CASE
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
            THEN ARRAY(SELECT TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'))))
            ELSE '{}'::varchar[]
        END AS ParsedTags,
        p.AcceptedAnswerId,
        -- Nested subquery: check if the post was closed due to specific reasons (Duplicate or Off-topic)
        EXISTS (
            SELECT 1
            FROM PostHistory ph_close
            WHERE ph_close.PostId = p.Id
              AND ph_close.PostHistoryTypeId = 10 -- Post Closed
              AND ph_close.Comment IN ('101', '102') -- Specific CloseReasonTypes IDs
        ) AS IsClosedDueToDuplicateOrOffTopic,
        COUNT(DISTINCT ph.Id) AS TotalHistoryEntries,
        MAX(ph.CreationDate) AS LastHistoryDate,
        -- Conditional aggregation: count specific edit-related history types
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 8, 9) THEN 1 ELSE 0 END) AS TotalEditHistoryEvents,
        -- Correlated subquery: check if any comment on this post contains a specific keyword (e.g., 'bug')
        EXISTS (
            SELECT 1
            FROM Comments co_corr
            WHERE co_corr.PostId = p.Id AND co_corr.Text ILIKE '%bug%'
        ) AS HasBugComment
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.Body, p.Tags, p.AcceptedAnswerId
),
PostVoteSummary AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotes -- For legacy favorite data
    FROM Votes v
    WHERE v.VoteTypeId IN (1, 2, 3, 5)
    GROUP BY v.PostId
),
UserPostTrends AS (
    SELECT
        pdh.OwnerUserId AS UserId,
        pdh.PostId,
        pdh.PostCreationDate,
        pdh.PostScore,
        COALESCE(pvs.UpVotesReceived, 0) AS PostUpVotes,
        COALESCE(pvs.DownVotesReceived, 0) AS PostDownVotes,
        COALESCE(pvs.AcceptedVotes, 0) AS PostAcceptedVotes,
        -- Window function: calculate rolling average post score for each user over a 30-day period
        AVG(pdh.PostScore) OVER (
            PARTITION BY pdh.OwnerUserId
            ORDER BY pdh.PostCreationDate
            RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW
        ) AS RollingAvgPostScoreLast30Days,
        -- Window function: get the score of the previous post by the same user
        LAG(pdh.PostScore, 1, 0) OVER (PARTITION BY pdh.OwnerUserId ORDER BY pdh.PostCreationDate) AS PreviousPostScore
    FROM PostDetailsWithHistory pdh
    LEFT JOIN PostVoteSummary pvs ON pdh.PostId = pvs.PostId
)
-- Main query: Combines user aggregates, post details, and trends for a comprehensive profile
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.LastAccessDate,
    ua.UserProfileViews,
    ua.UserUpVotes,
    ua.UserDownVotes,
    ua.TotalOwnedPosts,
    ua.OwnedQuestions,
    ua.OwnedAnswers,
    ua.TotalOwnedPostScore,
    ua.TotalOwnedPostViews,
    ua.TotalAnswersOnOwnedQuestions,
    ua.TotalOwnedPostFavorites,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.TotalCommentsMade,
    ua.LatestCommentTextByUser,
    ua.Location,
    SUM(upt.PostUpVotes) AS TotalUpVotesOnOwnedPosts,
    SUM(upt.PostDownVotes) AS TotalDownVotesOnOwnedPosts,
    SUM(upt.PostAcceptedVotes) AS TotalAcceptedAnswersContributed,
    -- Average of the rolling averages for a user's posts
    COALESCE(AVG(upt.RollingAvgPostScoreLast30Days), 0) AS OverallAvgRollingPostScore,
    -- Complicated calculation: User Activity Score, based on recency, longevity, and engagement
    (
        EXTRACT(EPOCH FROM (NOW() - ua.LastAccessDate)) / (60 * 60 * 24) * -0.1 + -- Penalize for inactivity (days)
        EXTRACT(EPOCH FROM (NOW() - ua.UserCreationDate)) / (60 * 60 * 24) * 0.01 + -- Reward for longevity (days)
        COALESCE(ua.OwnedQuestions + ua.OwnedAnswers, 0) * 0.5 +
        COALESCE(ua.TotalCommentsMade, 0) * 0.2
    )::numeric(10, 2) AS UserActivityScore,
    -- Complex calculation for an "Influence Score" combining various user and post metrics
    (
        ua.Reputation * 0.4 +
        COALESCE(ua.TotalOwnedPostScore, 0) * 0.2 +
        COALESCE(ua.GoldBadges, 0) * 10 +
        COALESCE(ua.SilverBadges, 0) * 5 +
        COALESCE(ua.BronzeBadges, 0) * 1 +
        COALESCE(ua.TotalCommentsMade, 0) * 0.05 +
        COALESCE(SUM(upt.PostUpVotes), 0) * 0.1 -
        COALESCE(SUM(upt.PostDownVotes), 0) * 0.05 +
        -- Penalize for posts that have comments mentioning 'bug'
        COALESCE(SUM(CASE WHEN pdh.HasBugComment THEN 1 ELSE 0 END), 0) * -2
    ) AS InfluenceScore,
    -- Window function: Rank users based on their calculated Influence Score
    RANK() OVER (
        ORDER BY
            (
                ua.Reputation * 0.4 +
                COALESCE(ua.TotalOwnedPostScore, 0) * 0.2 +
                COALESCE(ua.GoldBadges, 0) * 10 +
                COALESCE(ua.SilverBadges, 0) * 5 +
                COALESCE(ua.BronzeBadges, 0) * 1 +
                COALESCE(ua.TotalCommentsMade, 0) * 0.05 +
                COALESCE(SUM(upt.PostUpVotes), 0) * 0.1 -
                COALESCE(SUM(upt.PostDownVotes), 0) * 0.05 +
                COALESCE(SUM(CASE WHEN pdh.HasBugComment THEN 1 ELSE 0 END), 0) * -2
            ) DESC, ua.UserId
    ) AS InfluenceRank,
    -- Complicated CASE expression: categorize user's primary contribution focus
    CASE
        WHEN ua.OwnedQuestions > ua.OwnedAnswers * 2 AND ua.OwnedQuestions > 5 THEN 'Question-Focused'
        WHEN ua.OwnedAnswers > ua.OwnedQuestions * 2 AND ua.OwnedAnswers > 5 THEN 'Answer-Focused'
        WHEN ua.OwnedQuestions > 0 OR ua.OwnedAnswers > 0 THEN 'Balanced Contributor'
        ELSE 'Observer'
    END AS ContributionFocus,
    -- Correlated subquery with string aggregation: find top 5 most frequent tags for user's posts
    (
        SELECT STRING_AGG(DISTINCT tag_unnested, ', ')
        FROM PostDetailsWithHistory pdh_tags, UNNEST(pdh_tags.ParsedTags) AS tag_unnested
        WHERE pdh_tags.OwnerUserId = ua.UserId
        GROUP BY pdh_tags.OwnerUserId
        ORDER BY COUNT(tag_unnested) DESC
        LIMIT 5
    ) AS Top5TagsByPosts
FROM UserAggregates ua
LEFT JOIN UserPostTrends upt ON ua.UserId = upt.UserId
LEFT JOIN PostDetailsWithHistory pdh ON upt.PostId = pdh.PostId -- Re-join to access HasBugComment for InfluenceScore
WHERE
    ua.Reputation > 500 AND -- Filter for users with significant reputation
    ua.TotalOwnedPosts > 5 AND -- Ensure users have made a minimum number of posts
    (ua.GoldBadges > 0 OR ua.SilverBadges > 0) AND -- Users must have at least one high-tier badge
    (ua.Location IS NOT NULL AND ua.Location <> '') AND -- Exclude users without a specified location
    ua.DisplayName IS NOT NULL AND LENGTH(ua.DisplayName) > 2 AND -- Ensure DisplayName is valid
    EXISTS (
        -- Uncorrelated subquery: Check if the user has at least one highly viewed and scored question
        SELECT 1
        FROM Posts p_high_view
        WHERE p_high_view.OwnerUserId = ua.UserId
          AND p_high_view.PostTypeId = 1
          AND p_high_view.ViewCount > 10000
          AND p_high_view.Score > 50
    ) AND
    NOT EXISTS (
        -- Uncorrelated subquery: Exclude users whose average post score is significantly negative
        SELECT 1
        FROM Posts p_low_score
        WHERE p_low_score.OwnerUserId = ua.UserId
        GROUP BY p_low_score.OwnerUserId
        HAVING AVG(p_low_score.Score) < -5
    )
GROUP BY
    ua.UserId, ua.DisplayName, ua.Reputation, ua.UserCreationDate, ua.LastAccessDate, ua.UserProfileViews,
    ua.UserUpVotes, ua.UserDownVotes, ua.TotalOwnedPosts, ua.OwnedQuestions, ua.OwnedAnswers,
    ua.TotalOwnedPostScore, ua.TotalOwnedPostViews, ua.TotalAnswersOnOwnedQuestions,
    ua.TotalOwnedPostFavorites, ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges,
    ua.TotalCommentsMade, ua.LatestCommentTextByUser, ua.Location
HAVING
    COALESCE(SUM(upt.PostUpVotes), 0) > COALESCE(SUM(upt.PostDownVotes), 0) * 1.5 AND -- More upvotes than downvotes
    COALESCE(AVG(upt.RollingAvgPostScoreLast30Days), 0) > 0 -- Positive average post score trend
ORDER BY
    InfluenceRank ASC, UserActivityScore DESC
LIMIT 100;
