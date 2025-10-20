-- {"query": "49056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2324} 

WITH UserPostMetrics AS (
    -- Aggregates various post-related statistics for each user, including accepted answers they provided
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(p.Score) AS TotalPostScore,
        SUM(p.ViewCount) AS TotalPostViews,
        SUM(p.FavoriteCount) AS TotalPostFavorites,
        -- Count answers by this user that were accepted by the question's owner
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND parent_q.AcceptedAnswerId = p.Id THEN p.Id END) AS AcceptedAnswersGiven
    FROM Posts p
    LEFT JOIN Posts parent_q ON p.ParentId = parent_q.Id AND p.PostTypeId = 2 -- Join answers to their parent questions
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentMetrics AS (
    -- Aggregates comment-related statistics for each user
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalCommentsMade,
        SUM(c.Score) AS TotalCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserBadgeMetrics AS (
    -- Aggregates badge counts by class for each user
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteReceivedMetrics AS (
    -- Aggregates upvotes and downvotes received on posts owned by each user
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesReceived, -- VoteTypeId 2 is UpMod (upvote)
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvotesReceived -- VoteTypeId 3 is DownMod (downvote)
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserPostHistoryMetrics AS (
    -- Aggregates post history events (like edits or rollbacks) made by each user
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS TotalHistoryEntries,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS TotalEditsMade, -- Edit Title, Body, Tags
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN ph.Id END) AS TotalRollbacksMade -- Rollback Title, Body, Tags
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
PopularTagContributions AS (
    -- Identifies users who have contributed to posts tagged with a set of predefined popular tags.
    -- This CTE involves string manipulation and unnesting, stressing text processing capabilities.
    SELECT DISTINCT
        p.OwnerUserId AS UserId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
      AND p.Tags IS NOT NULL
      AND (
            p.Tags LIKE '%<javascript>%' OR p.Tags LIKE '%<python>%' OR p.Tags LIKE '%<c#>%<' OR
            p.Tags LIKE '%<java>%' OR p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<html%>' OR
            p.Tags LIKE '%<css>%' OR p.Tags LIKE '%<r>%' OR p.Tags LIKE '%<node.js>%' OR
            p.Tags LIKE '%<reactjs>%' OR p.Tags LIKE '%<angular>%' OR p.Tags LIKE '%<php>%'
          )
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Views AS ProfileViews,
    u.UpVotes AS UserGivenUpvotes, -- Total upvotes given *by* the user to others' posts
    u.DownVotes AS UserGivenDownvotes, -- Total downvotes given *by* the user to others' posts
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    COALESCE(upm.TotalPosts, 0) AS TotalPosts,
    COALESCE(upm.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(upm.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(upm.AcceptedAnswersGiven, 0) AS AcceptedAnswersGiven,
    COALESCE(upm.TotalPostScore, 0) AS TotalPostScore,
    COALESCE(upm.TotalPostViews, 0) AS TotalPostViews,
    COALESCE(upm.TotalPostFavorites, 0) AS TotalPostFavorites,
    COALESCE(ucm.TotalCommentsMade, 0) AS TotalCommentsMade,
    COALESCE(ucm.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(ubm.TotalBadges, 0) AS TotalBadges,
    COALESCE(ubm.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubm.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubm.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(uvrm.UpvotesReceived, 0) AS UpvotesReceived,
    COALESCE(uvrm.DownvotesReceived, 0) AS DownvotesReceived,
    COALESCE(uhm.TotalEditsMade, 0) AS TotalEditsMade,
    COALESCE(uhm.TotalRollbacksMade, 0) AS TotalRollbacksMade,
    COUNT(DISTINCT ptc.TagName) AS ContributedToPopularTagsCount,
    -- Calculate user tenure on the platform in years
    DATE_PART('year', AGE(CURRENT_TIMESTAMP, u.CreationDate)) AS YearsOnPlatform,
    -- Snippet of 'AboutMe' for text field retrieval
    SUBSTRING(u.AboutMe, 1, 250) AS AboutMeSnippet,
    -- Custom composite influence score for ranking based on various weighted metrics
    (
        u.Reputation * 0.4 +
        COALESCE(upm.TotalPostScore, 0) * 0.2 +
        COALESCE(uvrm.UpvotesReceived, 0) * 0.15 +
        COALESCE(ubm.GoldBadges, 0) * 10 +
        COALESCE(ubm.SilverBadges, 0) * 5 +
        COALESCE(ubm.BronzeBadges, 0) * 1 +
        COALESCE(upm.AcceptedAnswersGiven, 0) * 2 +
        COALESCE(uhm.TotalEditsMade, 0) * 0.1
    ) AS OverallInfluenceScore,
    -- Rank users based on their overall engagement and influence
    DENSE_RANK() OVER (
        ORDER BY
            u.Reputation DESC,
            COALESCE(upm.TotalPostScore, 0) DESC,
            COALESCE(uvrm.UpvotesReceived, 0) DESC,
            COALESCE(ubm.GoldBadges, 0) DESC,
            COALESCE(upm.TotalPosts, 0) DESC,
            COALESCE(ucm.TotalCommentsMade, 0) DESC
    ) AS UserEngagementRank
FROM Users u
LEFT JOIN UserPostMetrics upm ON u.Id = upm.UserId
LEFT JOIN UserCommentMetrics ucm ON u.Id = ucm.UserId
LEFT JOIN UserBadgeMetrics ubm ON u.Id = ubm.UserId
LEFT JOIN UserVoteReceivedMetrics uvrm ON u.Id = uvrm.UserId
LEFT JOIN UserPostHistoryMetrics uhm ON u.Id = uhm.UserId
LEFT JOIN PopularTagContributions ptc ON u.Id = ptc.UserId
WHERE
    u.Reputation >= 5000 -- Filter for users with significant reputation
    AND u.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '2 year' -- Ensure recent activity
    AND (u.DisplayName IS NOT NULL AND LENGTH(TRIM(u.DisplayName)) > 3) -- Filter for users with a valid DisplayName
    AND u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 50 -- Ensure 'AboutMe' is substantial
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate, u.Location, u.AboutMe,
    upm.TotalPosts, upm.TotalQuestions, upm.TotalAnswers, upm.AcceptedAnswersGiven, upm.TotalPostScore, upm.TotalPostViews, upm.TotalPostFavorites,
    ucm.TotalCommentsMade, ucm.TotalCommentScore,
    ubm.TotalBadges, ubm.GoldBadges, ubm.SilverBadges, ubm.BronzeBadges,
    uvrm.UpvotesReceived, uvrm.DownvotesReceived,
    uhm.TotalEditsMade, uhm.TotalRollbacksMade
HAVING COUNT(DISTINCT ptc.TagName) >= 2 -- Users must have contributed to at least 2 of the popular tags
ORDER BY OverallInfluenceScore DESC, UserEngagementRank ASC
LIMIT 5000;
