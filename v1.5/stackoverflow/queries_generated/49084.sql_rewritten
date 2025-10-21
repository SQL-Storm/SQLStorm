-- {"query": "49084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2489} 
WITH UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(p.Score) AS TotalPostScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1 AND p.FavoriteCount >= 50) AS HighFavoriteQuestions,
        MAX(p.CreationDate) AS LastPostDate,
        SUM(p.ViewCount) AS TotalViewCount
    FROM Users AS u
    INNER JOIN Posts AS p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 years') -- Focus on relatively recent activity
      AND u.Reputation >= 1000 -- Filter for established users
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    HAVING COUNT(DISTINCT p.Id) > 10 -- Only users with a minimum number of posts
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate,
        SUM(c.Score) AS TotalCommentScore
    FROM Comments AS c
    WHERE c.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 years')
    GROUP BY c.UserId
    HAVING COUNT(c.Id) > 5 -- Only users with a minimum number of comments
),
UserBadgeAwards AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS UniqueBadgeTypes,
        COUNT(b.Id) FILTER (WHERE b.TagBased = TRUE) AS TagBasedBadges
    FROM Badges AS b
    WHERE b.Date >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 years')
    GROUP BY b.UserId
),
UserTagEngagement AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT tags_array.tag_name) AS DistinctTagsContributed,
        STRING_AGG(DISTINCT tags_array.tag_name, ', ' ORDER BY tags_array.tag_name) AS TopTagsSummary,
        -- Calculate total score for posts associated with distinct tags
        SUM(p.Score) AS ScoreFromTaggedPosts
    FROM Posts AS p,
         LATERAL UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) AS tags_array(tag_name)
    WHERE p.PostTypeId = 1 -- Only questions contribute to tag diversity in this context
      AND p.OwnerUserId IS NOT NULL
      AND p.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 years')
      AND p.Score > 5
      AND LENGTH(tags_array.tag_name) > 0
    GROUP BY p.OwnerUserId
    HAVING COUNT(DISTINCT tags_array.tag_name) > 2 -- Users engaging with at least 3 distinct tags
),
PostHistoryAgg AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS EditHistoryCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosedEvent, -- At least one closure event in history
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopenedEvent,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate ELSE NULL END) AS LastEditHistoryDate
    FROM PostHistory AS ph
    WHERE ph.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 years')
    GROUP BY ph.PostId
),
UserPostHistorySummary AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(pha.EditHistoryCount) AS TotalPostEditEvents,
        SUM(pha.WasClosedEvent) AS TotalPostsWithClosureEvents,
        SUM(pha.WasReopenedEvent) AS TotalPostsWithReopenEvents,
        AVG(pha.EditHistoryCount) AS AvgEditEventsPerPost
    FROM Posts AS p
    INNER JOIN PostHistoryAgg AS pha ON p.Id = pha.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.TotalPosts,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.TotalPostScore,
    COALESCE(ups.AvgQuestionScore, 0.0) AS AvgQuestionScore,
    COALESCE(ups.AvgAnswerScore, 0.0) AS AvgAnswerScore,
    ups.HighFavoriteQuestions,
    ups.TotalViewCount,
    COALESCE(ucs.TotalComments, 0) AS TotalComments,
    COALESCE(ucs.AvgCommentScore, 0.0) AS AvgCommentScore,
    COALESCE(ucs.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(uba.TotalBadges, 0) AS TotalBadges,
    COALESCE(uba.GoldBadges, 0) AS GoldBadges,
    COALESCE(uba.SilverBadges, 0) AS SilverBadges,
    COALESCE(uba.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(uba.UniqueBadgeTypes, 0) AS UniqueBadgeTypes,
    COALESCE(uba.TagBasedBadges, 0) AS TagBasedBadges,
    COALESCE(ute.DistinctTagsContributed, 0) AS DistinctTagsContributed,
    COALESCE(ute.TopTagsSummary, 'N/A') AS TopTagsSummary,
    COALESCE(ute.ScoreFromTaggedPosts, 0) AS ScoreFromTaggedPosts,
    COALESCE(uphs.TotalPostEditEvents, 0) AS TotalPostEditEvents,
    COALESCE(uphs.TotalPostsWithClosureEvents, 0) AS TotalPostsWithClosureEvents,
    COALESCE(uphs.TotalPostsWithReopenEvents, 0) AS TotalPostsWithReopenEvents,
    COALESCE(uphs.AvgEditEventsPerPost, 0.0) AS AvgEditEventsPerPost,
    EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - ups.UserCreationDate)) / 86400 AS DaysSinceUserCreation,
    EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - ups.LastAccessDate)) / 86400 AS DaysSinceLastAccess,
    -- Calculate a comprehensive "Community Influence Score" based on various weighted metrics
    (
        (ups.Reputation * 0.05)                                 -- Base reputation contribution
        + (ups.TotalPostScore * 0.2)                            -- Impact of post scores
        + (ups.HighFavoriteQuestions * 5)                       -- Bonus for highly favorited questions
        + ((ups.QuestionCount + ups.AnswerCount) * 1.5)         -- Activity contribution (questions & answers)
        + (COALESCE(ucs.TotalComments, 0) * 0.3)                -- Comment activity
        + (COALESCE(uba.GoldBadges, 0) * 8)                     -- High value for gold badges
        + (COALESCE(uba.SilverBadges, 0) * 3)                   -- Medium value for silver badges
        + (COALESCE(uba.BronzeBadges, 0) * 0.5)                 -- Low value for bronze badges
        + (COALESCE(ute.DistinctTagsContributed, 0) * 1)        -- Value for diverse tag engagement
        + (COALESCE(uphs.TotalPostEditEvents, 0) * 0.1)         -- Slight bonus for editing/maintaining content
        - (COALESCE(uphs.TotalPostsWithClosureEvents, 0) * 3)   -- Penalty for posts that had closure events
        + (COALESCE(uphs.TotalPostsWithReopenEvents, 0) * 2)    -- Partial recovery for reopened posts
    ) AS CommunityInfluenceScore,
    RANK() OVER (ORDER BY (
        (ups.Reputation * 0.05)
        + (ups.TotalPostScore * 0.2)
        + (ups.HighFavoriteQuestions * 5)
        + ((ups.QuestionCount + ups.AnswerCount) * 1.5)
        + (COALESCE(ucs.TotalComments, 0) * 0.3)
        + (COALESCE(uba.GoldBadges, 0) * 8)
        + (COALESCE(uba.SilverBadges, 0) * 3)
        + (COALESCE(uba.BronzeBadges, 0) * 0.5)
        + (COALESCE(ute.DistinctTagsContributed, 0) * 1)
        + (COALESCE(uphs.TotalPostEditEvents, 0) * 0.1)
        - (COALESCE(uphs.TotalPostsWithClosureEvents, 0) * 3)
        + (COALESCE(uphs.TotalPostsWithReopenEvents, 0) * 2)
    ) DESC) AS InfluenceRank
FROM UserPostStats AS ups
LEFT JOIN UserCommentStats AS ucs ON ups.UserId = ucs.UserId
LEFT JOIN UserBadgeAwards AS uba ON ups.UserId = uba.UserId
LEFT JOIN UserTagEngagement AS ute ON ups.UserId = ute.UserId
LEFT JOIN UserPostHistorySummary AS uphs ON ups.UserId = uphs.UserId
WHERE ups.LastAccessDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year') -- Ensure users are recently active
  AND ups.Reputation >= 5000 -- More stringent reputation filter for final output set
ORDER BY InfluenceRank ASC, ups.Reputation DESC
LIMIT 100;