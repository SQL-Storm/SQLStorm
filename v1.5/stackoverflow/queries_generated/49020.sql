-- {"query": "49020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2401} 

WITH RelevantTags AS (
    SELECT 'sql' AS TagName
    UNION ALL SELECT 'performance'
    UNION ALL SELECT 'database'
    UNION ALL SELECT 'optimization'
    UNION ALL SELECT 'query-performance'
    UNION ALL SELECT 'postgresql'
    UNION ALL SELECT 'mysql'
    UNION ALL SELECT 'sql-server'
),
UserPostActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsOwnedCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersOwnedCount,
        COALESCE(SUM(p.Score), 0) AS TotalPostsScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalPostsViewCount,
        COALESCE(SUM(p.FavoriteCount), 0) AS TotalPostsFavoriteCount,
        COALESCE(SUM(p.CommentCount), 0) AS TotalCommentsOnOwnedPosts,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        ARRAY_AGG(DISTINCT rt.TagName) FILTER (WHERE rt.TagName IS NOT NULL) AS UserRelevantTags
    FROM Users AS u
    INNER JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN (
        SELECT
            p_inner.Id,
            UNNEST(string_to_array(substring(p_inner.Tags, 2, length(p_inner.Tags)-2), '><')) AS TagName
        FROM Posts AS p_inner
        WHERE p_inner.Tags IS NOT NULL AND p_inner.Tags != ''
    ) AS post_tags ON p.Id = post_tags.Id
    INNER JOIN RelevantTags AS rt ON post_tags.TagName = rt.TagName -- Filter posts by relevant tags
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserCommentContributionSummary AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentsMadeCount,
        COALESCE(SUM(c.Score), 0) AS TotalCommentsMadeScore,
        COUNT(DISTINCT c.PostId) AS UniquePostsCommentedOn
    FROM Comments AS c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserBadgeAchievementSummary AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgesReceived,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadgesReceived,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadgesReceived,
        COUNT(CASE WHEN b.TagBased = TRUE THEN 1 END) AS TagBasedBadgesReceived
    FROM Badges AS b
    GROUP BY b.UserId
),
UserPostEditRevisionSummary AS (
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS PostEditsMadeCount,
        COUNT(DISTINCT ph.PostId) AS UniquePostsEditedCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 24) -- Edit Title, Body, Tags, Rollbacks, Suggested Edit Applied
          AND ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
UserVoteReceivedSummary AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesOnOwnedPosts,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesOnOwnedPosts
    FROM Votes AS v
    INNER JOIN Posts AS p ON v.PostId = p.Id
    WHERE v.VoteTypeId IN (2, 3) -- UpMod, DownMod
          AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalPostsOwned,
    uas.QuestionsOwnedCount,
    uas.AnswersOwnedCount,
    uas.TotalPostsScore,
    uas.TotalPostsViewCount,
    uas.TotalPostsFavoriteCount,
    uas.TotalCommentsOnOwnedPosts,
    COALESCE(uccs.CommentsMadeCount, 0) AS CommentsMadeCount,
    COALESCE(uccs.TotalCommentsMadeScore, 0) AS TotalCommentsMadeScore,
    COALESCE(uccs.UniquePostsCommentedOn, 0) AS UniquePostsCommentedOn,
    COALESCE(ubas.GoldBadgesReceived, 0) AS GoldBadges,
    COALESCE(ubas.SilverBadgesReceived, 0) AS SilverBadges,
    COALESCE(ubas.BronzeBadgesReceived, 0) AS BronzeBadges,
    COALESCE(ubas.TagBasedBadgesReceived, 0) AS TagBasedBadges,
    COALESCE(upers.PostEditsMadeCount, 0) AS PostEditsMade,
    COALESCE(upers.UniquePostsEditedCount, 0) AS UniquePostsEdited,
    COALESCE(uvrs.UpVotesOnOwnedPosts, 0) AS UpVotesReceived,
    COALESCE(uvrs.DownVotesOnOwnedPosts, 0) AS DownVotesReceived,
    -- Calculate a comprehensive 'InfluenceScore'
    (
        (uas.Reputation * 0.1) +
        (uas.TotalPostsScore * 0.7) +
        (uas.TotalPostsViewCount * 0.005) +
        (uas.TotalPostsFavoriteCount * 0.3) +
        (uas.TotalCommentsOnOwnedPosts * 0.15) +
        (COALESCE(uccs.CommentsMadeCount, 0) * 0.08) +
        (COALESCE(uccs.TotalCommentsMadeScore, 0) * 0.02) +
        (COALESCE(ubas.GoldBadgesReceived, 0) * 20) +
        (COALESCE(ubas.SilverBadgesReceived, 0) * 10) +
        (COALESCE(ubas.BronzeBadgesReceived, 0) * 2) +
        (COALESCE(ubas.TagBasedBadgesReceived, 0) * 5) +
        (COALESCE(upers.PostEditsMadeCount, 0) * 0.05) +
        (COALESCE(uvrs.UpVotesOnOwnedPosts, 0) * 0.5) -
        (COALESCE(uvrs.DownVotesOnOwnedPosts, 0) * 0.2)
    ) AS InfluenceScore,
    -- Calculate User Engagement Score based on activity recency and breadth
    (
        EXTRACT(EPOCH FROM (NOW() - uas.LastAccessDate)) / 86400.0 * -0.01 + -- Penalize for older access
        EXTRACT(EPOCH FROM (NOW() - uas.LastPostActivityDate)) / 86400.0 * -0.005 + -- Penalize for older post activity
        (uas.QuestionsOwnedCount * 0.5 + uas.AnswersOwnedCount * 0.3 + COALESCE(uccs.UniquePostsCommentedOn, 0) * 0.2 + COALESCE(upers.UniquePostsEditedCount, 0) * 0.1) -- Reward for diverse activity
    ) AS EngagementScore,
    -- Rank users based on their influence and engagement scores
    DENSE_RANK() OVER (ORDER BY (
        (uas.Reputation * 0.1) +
        (uas.TotalPostsScore * 0.7) +
        (uas.TotalPostsViewCount * 0.005) +
        (uas.TotalPostsFavoriteCount * 0.3) +
        (uas.TotalCommentsOnOwnedPosts * 0.15) +
        (COALESCE(uccs.CommentsMadeCount, 0) * 0.08) +
        (COALESCE(uccs.TotalCommentsMadeScore, 0) * 0.02) +
        (COALESCE(ubas.GoldBadgesReceived, 0) * 20) +
        (COALESCE(ubas.SilverBadgesReceived, 0) * 10) +
        (COALESCE(ubas.BronzeBadgesReceived, 0) * 2) +
        (COALESCE(ubas.TagBasedBadgesReceived, 0) * 5) +
        (COALESCE(upers.PostEditsMadeCount, 0) * 0.05) +
        (COALESCE(uvrs.UpVotesOnOwnedPosts, 0) * 0.5) -
        (COALESCE(uvrs.DownVotesOnOwnedPosts, 0) * 0.2)
    ) DESC, uas.Reputation DESC, uas.UserId ASC) AS OverallInfluenceRank
FROM UserPostActivitySummary AS uas
LEFT JOIN UserCommentContributionSummary AS uccs ON uas.UserId = uccs.UserId
LEFT JOIN UserBadgeAchievementSummary AS ubas ON uas.UserId = ubas.UserId
LEFT JOIN UserPostEditRevisionSummary AS upers ON uas.UserId = upers.UserId
LEFT JOIN UserVoteReceivedSummary AS uvrs ON uas.UserId = uvrs.UserId
WHERE uas.Reputation > 5000 -- Filter for established users
  AND uas.TotalPostsOwned > 10 -- Require a minimum number of relevant posts
  AND uas.UserCreationDate < (NOW() - INTERVAL '2 years') -- User account must be older than 2 years
  AND EXISTS (SELECT 1 FROM RelevantTags rt_check WHERE rt_check.TagName = ANY(uas.UserRelevantTags)) -- Ensure at least one relevant tag is present
ORDER BY InfluenceScore DESC, EngagementScore DESC
LIMIT 200;
