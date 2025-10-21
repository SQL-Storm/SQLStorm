-- {"query": "19084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3951} 

WITH UserBaseInfo AS (
    -- CTE 1: Basic user information with initial filtering and a window function for reputation ranking.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.WebsiteUrl,
        u.Location,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserTotalUpVotesGiven,
        u.DownVotes AS UserTotalDownVotesGiven,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS RankInLocation
    FROM Users u
    WHERE u.Reputation > 500 -- Filter for more engaged users
      AND u.LastAccessDate > CURRENT_DATE - INTERVAL '2 year' -- Active in the last 2 years
      AND u.DisplayName IS NOT NULL
),
PostContentAnalysis AS (
    -- CTE 2: Extracts tags, calculates post-level metrics, and includes correlated subqueries for related posts.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastEditDate,
        p.Title,
        COALESCE(LOWER(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))), 'untagged') AS TagName, -- String manipulation & NULL logic
        LENGTH(p.Body) AS BodyLength,
        CHAR_LENGTH(REPLACE(p.Body, ' ', '')) AS BodyCharCountNoSpaces,
        (SELECT MAX(pa.Score) FROM Posts pa WHERE pa.ParentId = p.Id AND pa.PostTypeId = 2) AS MaxAnswerScoreForQuestion, -- Correlated subquery
        (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS LinkedPostsCount, -- Correlated subquery
        (SELECT COUNT(DISTINCT ph.UserId) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS UniqueEditorsCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions or Answers
      AND p.OwnerUserId IS NOT NULL
      AND p.CreationDate IS NOT NULL
),
PostActivityMetrics AS (
    -- CTE 3: Aggregates post history and vote data per post.
    SELECT
        pc.PostId,
        pc.OwnerUserId,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS TotalEditHistoryEntries,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS TotalCloseHistoryEntries,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 11) AS TotalReopenHistoryEntries,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS ReceivedUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS ReceivedDownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS ReceivedFavoriteVotes,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyPosted,
        SUM(CASE WHEN v.VoteTypeId = 9 THEN v.BountyAmount ELSE 0 END) AS TotalBountyReceivedOnPost,
        MAX(v.CreationDate) AS LastVoteDate
    FROM PostContentAnalysis pc
    LEFT JOIN PostHistory ph ON pc.PostId = ph.PostId
    LEFT JOIN Votes v ON pc.PostId = v.PostId
    GROUP BY pc.PostId, pc.OwnerUserId
),
UserOverallEngagement AS (
    -- CTE 4: Consolidates user-level metrics from various sources.
    SELECT
        ubi.UserId,
        ubi.DisplayName,
        ubi.Reputation,
        ubi.UserCreationDate,
        ubi.LastAccessDate,
        ubi.ReputationRank,
        ubi.RankInLocation,
        ubi.UserTotalUpVotesGiven,
        ubi.UserTotalDownVotesGiven,
        COUNT(DISTINCT pca.PostId) FILTER (WHERE pca.PostTypeId = 1) AS TotalQuestionsOwned,
        COUNT(DISTINCT pca.PostId) FILTER (WHERE pca.PostTypeId = 2) AS TotalAnswersOwned,
        SUM(pca.PostScore) AS TotalScoreOnOwnedPosts,
        AVG(pca.PostScore) FILTER (WHERE pca.PostTypeId = 1) AS AvgQuestionScoreOwned,
        AVG(pca.PostScore) FILTER (WHERE pca.PostTypeId = 2) AS AvgAnswerScoreOwned,
        SUM(pca.PostViewCount) AS TotalPostViewsOwned,
        SUM(pca.FavoriteCount) AS TotalFavoritesOnOwnedPosts,
        COUNT(DISTINCT pca.TagName) FILTER (WHERE pca.TagName != 'untagged') AS UniqueTagsUsed,
        SUM(pca.MaxAnswerScoreForQuestion) AS MaxScoresOfAnswersToOwnedQuestions,
        SUM(pca.LinkedPostsCount) AS TotalLinkedPostsFromOwnedQuestions,
        SUM(pca.BodyLength) FILTER (WHERE pca.PostTypeId = 1) AS TotalQuestionBodyLength,
        SUM(pca.BodyLength) FILTER (WHERE pca.PostTypeId = 2) AS TotalAnswerBodyLength,
        SUM(pam.TotalEditHistoryEntries) AS TotalOwnedPostEditHistory,
        SUM(pam.TotalCloseHistoryEntries) AS TotalOwnedPostCloseHistory,
        SUM(pam.ReceivedUpVotes) AS TotalReceivedUpVotesOnOwnedPosts,
        SUM(pam.ReceivedDownVotes) AS TotalReceivedDownVotesOnOwnedPosts,
        SUM(pam.ReceivedFavoriteVotes) AS TotalReceivedFavoriteVotesOnOwnedPosts,
        SUM(pam.TotalBountyPosted) AS TotalBountyGivenByOwner,
        SUM(pam.TotalBountyReceivedOnPost) AS TotalBountyReceivedByOwner,
        COALESCE(MAX(c.CreationDate), '1900-01-01') AS LastCommentDate, -- NULL logic: COALESCE
        COUNT(DISTINCT c.Id) AS TotalCommentsMade
    FROM UserBaseInfo ubi
    LEFT JOIN PostContentAnalysis pca ON ubi.UserId = pca.OwnerUserId
    LEFT JOIN PostActivityMetrics pam ON pca.PostId = pam.PostId AND ubi.UserId = pam.OwnerUserId
    LEFT JOIN Comments c ON ubi.UserId = c.UserId
    GROUP BY ubi.UserId, ubi.DisplayName, ubi.Reputation, ubi.UserCreationDate, ubi.LastAccessDate, ubi.ReputationRank, ubi.RankInLocation, ubi.UserTotalUpVotesGiven, ubi.UserTotalDownVotesGiven
),
BadgeInfo AS (
    -- CTE 5: Aggregates badge information per user.
    SELECT
        b.UserId,
        STRING_AGG(b.Name, ';') FILTER (WHERE b.Class = 1) AS GoldBadges,
        STRING_AGG(b.Name, ';') FILTER (WHERE b.Class = 2) AS SilverBadges,
        STRING_AGG(b.Name, ';') FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
FinalUserPerformance AS (
    -- Combine users with posts and users with only comments.
    -- Branch 1: Users who own posts
    SELECT
        uoe.UserId,
        uoe.DisplayName,
        uoe.Reputation,
        uoe.ReputationRank,
        uoe.UserCreationDate,
        uoe.LastAccessDate,
        uoe.UserTotalUpVotesGiven,
        uoe.UserTotalDownVotesGiven,
        uoe.TotalQuestionsOwned,
        uoe.TotalAnswersOwned,
        uoe.TotalScoreOnOwnedPosts,
        uoe.AvgQuestionScoreOwned,
        uoe.AvgAnswerScoreOwned,
        uoe.TotalPostViewsOwned,
        uoe.TotalFavoritesOnOwnedPosts,
        uoe.UniqueTagsUsed,
        uoe.MaxScoresOfAnswersToOwnedQuestions,
        uoe.TotalLinkedPostsFromOwnedQuestions,
        uoe.TotalQuestionBodyLength,
        uoe.TotalAnswerBodyLength,
        uoe.TotalOwnedPostEditHistory,
        uoe.TotalOwnedPostCloseHistory,
        uoe.TotalReceivedUpVotesOnOwnedPosts,
        uoe.TotalReceivedDownVotesOnOwnedPosts,
        uoe.TotalReceivedFavoriteVotesOnOwnedPosts,
        uoe.TotalBountyGivenByOwner,
        uoe.TotalBountyReceivedByOwner,
        uoe.LastCommentDate,
        uoe.TotalCommentsMade,
        bi.GoldBadges,
        bi.SilverBadges,
        bi.BronzeBadges,
        bi.TotalBadges,
        'HasPosts' AS EngagementSegment
    FROM UserOverallEngagement uoe
    LEFT JOIN BadgeInfo bi ON uoe.UserId = bi.UserId
    WHERE uoe.TotalQuestionsOwned > 0 OR uoe.TotalAnswersOwned > 0

    UNION ALL -- Set operator: UNION ALL to combine with users who only comment

    -- Branch 2: Users who ONLY comment (no owned posts)
    SELECT
        ubi.UserId,
        ubi.DisplayName,
        ubi.Reputation,
        ubi.ReputationRank,
        ubi.UserCreationDate,
        ubi.LastAccessDate,
        ubi.UserTotalUpVotesGiven,
        ubi.UserTotalDownVotesGiven,
        0 AS TotalQuestionsOwned,
        0 AS TotalAnswersOwned,
        0 AS TotalScoreOnOwnedPosts,
        0.0 AS AvgQuestionScoreOwned,
        0.0 AS AvgAnswerScoreOwned,
        0 AS TotalPostViewsOwned,
        0 AS TotalFavoritesOnOwnedPosts,
        0 AS UniqueTagsUsed,
        0 AS MaxScoresOfAnswersToOwnedQuestions,
        0 AS TotalLinkedPostsFromOwnedQuestions,
        0 AS TotalQuestionBodyLength,
        0 AS TotalAnswerBodyLength,
        0 AS TotalOwnedPostEditHistory,
        0 AS TotalOwnedPostCloseHistory,
        0 AS TotalReceivedUpVotesOnOwnedPosts,
        0 AS TotalReceivedDownVotesOnOwnedPosts,
        0 AS TotalReceivedFavoriteVotesOnOwnedPosts,
        0 AS TotalBountyGivenByOwner,
        0 AS TotalBountyReceivedByOwner,
        COALESCE(MAX(c.CreationDate), '1900-01-01') AS LastCommentDate,
        COUNT(c.Id) AS TotalCommentsMade,
        bi.GoldBadges,
        bi.SilverBadges,
        bi.BronzeBadges,
        bi.TotalBadges,
        'OnlyComments' AS EngagementSegment
    FROM UserBaseInfo ubi
    LEFT JOIN PostContentAnalysis pca ON ubi.UserId = pca.OwnerUserId -- Used to filter out users with posts
    JOIN Comments c ON ubi.UserId = c.UserId -- Requires comments
    LEFT JOIN BadgeInfo bi ON ubi.UserId = bi.UserId
    WHERE pca.PostId IS NULL -- Crucial NULL logic: Ensure no owned posts
    GROUP BY ubi.UserId, ubi.DisplayName, ubi.Reputation, ubi.UserCreationDate, ubi.LastAccessDate, ubi.ReputationRank, ubi.RankInLocation, ubi.UserTotalUpVotesGiven, ubi.UserTotalDownVotesGiven,
             bi.GoldBadges, bi.SilverBadges, bi.BronzeBadges, bi.TotalBadges
)
-- Final Selection and Calculations
SELECT
    fup.UserId,
    fup.DisplayName,
    fup.Reputation,
    fup.ReputationRank,
    fup.EngagementSegment,
    EXTRACT(YEAR FROM AGE(CURRENT_TIMESTAMP, fup.UserCreationDate)) AS YearsOnPlatform,
    fup.LastAccessDate,
    COALESCE(ROUND((fup.UserTotalUpVotesGiven::numeric - fup.UserTotalDownVotesGiven::numeric) / NULLIF((fup.UserTotalUpVotesGiven::numeric + fup.UserTotalDownVotesGiven::numeric), 0), 3), 0.0) AS GlobalNetVoteRatio, -- NULLIF for division by zero
    fup.TotalQuestionsOwned,
    fup.TotalAnswersOwned,
    fup.TotalCommentsMade,
    fup.TotalScoreOnOwnedPosts,
    fup.AvgQuestionScoreOwned,
    fup.AvgAnswerScoreOwned,
    fup.TotalPostViewsOwned,
    fup.TotalFavoritesOnOwnedPosts,
    fup.UniqueTagsUsed,
    fup.GoldBadges,
    fup.SilverBadges,
    fup.BronzeBadges,
    fup.TotalBadges,
    fup.TotalOwnedPostEditHistory,
    fup.TotalOwnedPostCloseHistory,
    fup.TotalReceivedUpVotesOnOwnedPosts,
    fup.TotalReceivedDownVotesOnOwnedPosts,
    COALESCE(ROUND(fup.TotalReceivedUpVotesOnOwnedPosts::numeric / NULLIF((fup.TotalReceivedUpVotesOnOwnedPosts + fup.TotalReceivedDownVotesOnOwnedPosts), 0), 3), 0.0) AS PostUpvoteRatio,
    fup.TotalBountyGivenByOwner,
    fup.TotalBountyReceivedByOwner,
    AGE(CURRENT_TIMESTAMP, fup.LastAccessDate) AS TimeSinceLastActivity,
    CASE
        WHEN fup.Reputation >= 50000 AND fup.TotalQuestionsOwned >= 200 AND fup.TotalAnswersOwned >= 500 AND fup.TotalBadges >= 50 THEN 'Supreme Guru'
        WHEN fup.Reputation >= 10000 AND fup.TotalQuestionsOwned >= 50 AND fup.TotalAnswersOwned >= 100 AND fup.TotalBadges >= 10 THEN 'Elite Contributor'
        WHEN fup.Reputation >= 2000 AND (fup.TotalQuestionsOwned + fup.TotalAnswersOwned + fup.TotalCommentsMade) >= 100 THEN 'Proactive Participant'
        WHEN fup.Reputation >= 500 AND (fup.TotalQuestionsOwned + fup.TotalAnswersOwned + fup.TotalCommentsMade) >= 20 THEN 'Engaged User'
        ELSE 'Infrequent User'
    END AS UserPersonaClassification,
    -- A very complex weighted score for influence and activity
    (
        COALESCE(fup.Reputation, 0) * 0.25
        + COALESCE(fup.TotalQuestionsOwned, 0) * 5
        + COALESCE(fup.TotalAnswersOwned, 0) * 3
        + COALESCE(fup.TotalCommentsMade, 0) * 0.5
        + COALESCE(fup.TotalScoreOnOwnedPosts, 0) * 0.1
        + COALESCE(fup.TotalPostViewsOwned, 0) * 0.005
        + COALESCE(fup.TotalFavoritesOnOwnedPosts, 0) * 2
        + COALESCE(fup.UniqueTagsUsed, 0) * 1
        + COALESCE(fup.MaxScoresOfAnswersToOwnedQuestions, 0) * 0.75
        + COALESCE(fup.TotalLinkedPostsFromOwnedQuestions, 0) * 1.5
        + COALESCE(fup.TotalOwnedPostEditHistory, 0) * 0.3
        + COALESCE(fup.TotalReceivedUpVotesOnOwnedPosts, 0) * 0.15
        - COALESCE(fup.TotalReceivedDownVotesOnOwnedPosts, 0) * 0.2
        + COALESCE(fup.TotalBountyGivenByOwner, 0) * 0.001
        + COALESCE(fup.TotalBountyReceivedByOwner, 0) * 0.005
        + COALESCE(fup.TotalBadges, 0) * 0.5
        + (CASE WHEN fup.LastAccessDate > CURRENT_DATE - INTERVAL '3 months' THEN 100 ELSE 0 END) -- Recency bonus
    ) AS CalculatedInfluenceScore
FROM FinalUserPerformance fup
WHERE fup.CalculatedInfluenceScore IS NOT NULL -- Exclude any users where the score calculation somehow failed
  AND fup.ReputationRank <= 10000 -- Focus on top N for performance and relevance
ORDER BY CalculatedInfluenceScore DESC, fup.LastAccessDate DESC, fup.Reputation DESC
LIMIT 5000;
