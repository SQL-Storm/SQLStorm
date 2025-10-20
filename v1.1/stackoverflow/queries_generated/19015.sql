-- {"query": "19015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3947} 

WITH UserActivityBase AS (
    -- Gathers fundamental activity metrics for each user, including post counts, scores, views, comments made, and votes cast/received.
    -- Filters for users created after a certain date to focus on a more relevant period.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsPosted,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersPosted,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(SUM(P.ViewCount), 0) AS TotalPostViews,
        COALESCE(SUM(P.CommentCount), 0) AS TotalPostComments,
        COALESCE(SUM(P.FavoriteCount), 0) AS TotalPostFavorites,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalUserCommentsMade,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpvotesReceivedOnPosts,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvotesReceivedOnPosts,
        COALESCE(SUM(CASE WHEN V_CAST.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpvotesCast,
        COALESCE(SUM(CASE WHEN V_CAST.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvotesCast
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3) -- Votes received on user's posts
    LEFT JOIN Votes V_CAST ON U.Id = V_CAST.UserId AND V_CAST.VoteTypeId IN (2, 3) -- Votes cast by the user
    WHERE U.CreationDate >= '2010-01-01'
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
UserBadgeSummary AS (
    -- Summarizes badge counts (Gold, Silver, Bronze) and flags for specific badge types.
    SELECT
        U.Id AS UserId,
        COALESCE(SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        MAX(CASE WHEN B.Name LIKE '%Constituent%' OR B.Name LIKE '%Fanatic%' THEN TRUE ELSE FALSE END) AS HasEngagementBadge,
        MAX(CASE WHEN B.Name LIKE '%Disciplined%' THEN TRUE ELSE FALSE END) AS HasDisciplinedBadge
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id
),
PostHistoryFlags AS (
    -- Identifies users who have had posts closed, community-owned, or migrated.
    SELECT
        P.OwnerUserId AS UserId,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN TRUE ELSE FALSE END) AS HasPostsClosed,
        MAX(CASE WHEN PH.PostHistoryTypeId = 16 THEN TRUE ELSE FALSE END) AS HasCommunityOwnedPosts,
        MAX(CASE WHEN PH.PostHistoryTypeId = 17 OR PH.PostHistoryTypeId IN (35, 36) THEN TRUE ELSE FALSE END) AS HasMigratedPosts
    FROM Posts P
    JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserCalculatedMetrics AS (
    -- Combines user activity, badge summary, and post history flags, then computes various performance ratios and tenure.
    -- Includes string manipulation on DisplayName.
    SELECT
        UAB.UserId,
        UAB.DisplayName,
        UAB.Reputation,
        UAB.UserCreationDate,
        UAB.LastAccessDate,
        UAB.QuestionsPosted,
        UAB.AnswersPosted,
        UAB.TotalPosts,
        UAB.TotalPostScore,
        UAB.TotalPostViews,
        UAB.TotalPostComments,
        UAB.TotalPostFavorites,
        UAB.TotalUserCommentsMade,
        UAB.UpvotesReceivedOnPosts,
        UAB.DownvotesReceivedOnPosts,
        UAB.UpvotesCast,
        UAB.DownvotesCast,
        UBS.GoldBadges,
        UBS.SilverBadges,
        UBS.BronzeBadges,
        UBS.HasEngagementBadge,
        UBS.HasDisciplinedBadge,
        COALESCE(PHF.HasPostsClosed, FALSE) AS HasPostsClosed,
        COALESCE(PHF.HasCommunityOwnedPosts, FALSE) AS HasCommunityOwnedPosts,
        COALESCE(PHF.HasMigratedPosts, FALSE) AS HasMigratedPosts,
        -- Performance metrics, handling division by zero with NULLIF
        CAST(UAB.TotalPostScore AS NUMERIC) / NULLIF(UAB.TotalPosts, 0) AS AvgScorePerPost,
        CAST(UAB.TotalPostViews AS NUMERIC) / NULLIF(UAB.TotalPosts, 0) AS AvgViewsPerPost,
        CAST(UAB.TotalUserCommentsMade AS NUMERIC) / NULLIF(UAB.TotalPosts, 0) AS CommentActivityRatio,
        CAST(UAB.UpvotesReceivedOnPosts AS NUMERIC) / NULLIF(UAB.DownvotesReceivedOnPosts, 0) AS UpToDownvoteRatioReceived,
        (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - UAB.UserCreationDate)) / (60 * 60 * 24 * 365.25)) AS UserTenureYears,
        LOWER(REPLACE(UAB.DisplayName, ' ', '')) AS ProcessedDisplayName
    FROM UserActivityBase UAB
    LEFT JOIN UserBadgeSummary UBS ON UAB.UserId = UBS.UserId
    LEFT JOIN PostHistoryFlags PHF ON UAB.UserId = PHF.UserId
    WHERE UAB.Reputation > 500
),
TagUsageAndPerformance AS (
    -- Extracts individual tags from posts and associates them with post scores and owner user IDs.
    -- Uses string manipulation as described in the schema for parsing Tags.
    SELECT
        TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName,
        P.Id AS PostId,
        P.OwnerUserId,
        P.Score
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 AND P.OwnerUserId IS NOT NULL
),
AggregatedTagStats AS (
    -- Calculates overall statistics for each tag, including popularity and average post score, and ranks them.
    SELECT
        TUP.TagName,
        COUNT(DISTINCT TUP.PostId) AS TaggedPostsCount,
        COALESCE(SUM(TUP.Score), 0) AS TotalScoreForTag,
        CAST(COALESCE(SUM(TUP.Score), 0) AS NUMERIC) / NULLIF(COUNT(DISTINCT TUP.PostId), 0) AS AvgScorePerTaggedPost,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT TUP.PostId) DESC) AS TagPopularityRank,
        DENSE_RANK() OVER (ORDER BY CAST(COALESCE(SUM(TUP.Score), 0) AS NUMERIC) / NULLIF(COUNT(DISTINCT TUP.PostId), 0) DESC NULLS LAST) AS TagPerformanceRank
    FROM TagUsageAndPerformance TUP
    GROUP BY TUP.TagName
),
UserTopTags AS (
    -- Determines each user's most frequently used tag.
    SELECT
        TUP.OwnerUserId AS UserId,
        TUP.TagName,
        COUNT(TUP.PostId) AS UserTagCount,
        ROW_NUMBER() OVER (PARTITION BY TUP.OwnerUserId ORDER BY COUNT(TUP.PostId) DESC, TUP.TagName) AS rn
    FROM TagUsageAndPerformance TUP
    WHERE TUP.OwnerUserId IS NOT NULL
    GROUP BY TUP.OwnerUserId, TUP.TagName
),
UserPostClosedDetails AS (
    -- Retrieves details for the most recent closed post for users who have had posts closed, including the close reason.
    SELECT
        P.OwnerUserId AS UserId,
        PH.PostId AS ClosedPostId,
        PH.CreationDate AS ClosedDate,
        CRT.Name AS CloseReason,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY PH.CreationDate DESC) AS rn
    FROM Posts P
    JOIN PostHistory PH ON P.Id = PH.PostId
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    LEFT JOIN CloseReasonTypes CRT ON PH.Comment = CAST(CRT.Id AS VARCHAR) -- Join on PostHistory.Comment for close reason ID
    WHERE PHT.Id IN (10, 101, 102, 103, 104, 105) AND P.OwnerUserId IS NOT NULL
)
-- Main query: Combines all derived user and tag metrics, applies complex filtering, and uses window functions for final rankings.
-- It also includes a UNION ALL to compare active, influential users with high-reputation, inactive users.
SELECT
    UCM.UserId,
    UCM.DisplayName,
    UCM.Reputation,
    UCM.ProcessedDisplayName,
    UCM.UserTenureYears,
    UCM.QuestionsPosted,
    UCM.AnswersPosted,
    UCM.TotalPosts,
    UCM.TotalPostScore,
    UCM.TotalPostViews,
    UCM.TotalPostComments,
    UCM.TotalPostFavorites,
    UCM.TotalUserCommentsMade,
    UCM.UpvotesReceivedOnPosts,
    UCM.DownvotesReceivedOnPosts,
    UCM.UpvotesCast,
    UCM.DownvotesCast,
    UCM.GoldBadges,
    UCM.SilverBadges,
    UCM.BronzeBadges,
    UCM.HasEngagementBadge,
    UCM.HasDisciplinedBadge,
    UCM.HasPostsClosed,
    UCM.HasCommunityOwnedPosts,
    UCM.HasMigratedPosts,
    UCM.AvgScorePerPost,
    UCM.AvgViewsPerPost,
    UCM.CommentActivityRatio,
    UCM.UpToDownvoteRatioReceived,
    ATS_Top1.TagName AS TopTag1,
    ATS_Top1.TaggedPostsCount AS TopTag1_Usage,
    ATS_Top1.AvgScorePerTaggedPost AS TopTag1_AvgScore,
    ATS_Top1.TagPopularityRank AS TopTag1_PopularityRank,
    ATS_Top1.TagPerformanceRank AS TopTag1_PerformanceRank,
    UCCD.ClosedPostId AS MostRecentClosedPostId,
    UCCD.ClosedDate AS MostRecentClosedDate,
    COALESCE(UCCD.CloseReason, 'Unknown/Legacy Reason') AS MostRecentCloseReason,
    -- Correlated Subquery: Checks if a user has ever linked their own posts (self-referential links).
    EXISTS (
        SELECT 1
        FROM PostLinks PL
        WHERE PL.PostId IN (SELECT P_self.Id FROM Posts P_self WHERE P_self.OwnerUserId = UCM.UserId)
          AND PL.RelatedPostId IN (SELECT P2_self.Id FROM Posts P2_self WHERE P2_self.OwnerUserId = UCM.UserId)
          AND PL.LinkTypeId = 1
        LIMIT 1
    ) AS HasSelfLinkedPosts,
    -- Window Function: Ranks users based on reputation, badges, and post performance.
    RANK() OVER (
        ORDER BY
            UCM.Reputation DESC,
            UCM.GoldBadges DESC,
            UCM.AvgScorePerPost DESC NULLS LAST,
            UCM.UpvotesReceivedOnPosts DESC
    ) AS OverallUserRank,
    -- Window Function: Assigns users to deciles based on recent activity and total posts, indicating activity tiers.
    NTILE(10) OVER (ORDER BY UCM.LastAccessDate DESC, UCM.TotalPosts DESC) AS UserActivityDecile
FROM UserCalculatedMetrics UCM
LEFT JOIN UserTopTags UTT_Top1 ON UCM.UserId = UTT_Top1.UserId AND UTT_Top1.rn = 1
LEFT JOIN AggregatedTagStats ATS_Top1 ON UTT_Top1.TagName = ATS_Top1.TagName
LEFT JOIN UserPostClosedDetails UCCD ON UCM.UserId = UCCD.UserId AND UCCD.rn = 1
WHERE
    UCM.Reputation > 1000
    AND UCM.TotalPosts > 5
    AND (UCM.GoldBadges > 0 OR UCM.HasEngagementBadge)
    AND (
        UCM.AvgScorePerPost IS NULL OR UCM.AvgScorePerPost > 2
        OR UCM.UpToDownvoteRatioReceived > 5
        OR UCM.CommentActivityRatio > 0.5
    )
    AND (NOT UCM.HasPostsClosed OR UCM.MostRecentCloseReason LIKE '%duplicate%') -- NULL logic: not closed OR closed for duplicate reason
    AND LENGTH(UCM.DisplayName) > 3
    AND UCM.DisplayName NOT LIKE '%test%' -- String expression exclusion
    
UNION ALL -- Set operator: Combines the above result with a set of high-reputation, but inactive users.

SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    LOWER(REPLACE(U.DisplayName, ' ', '')) AS ProcessedDisplayName,
    (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - U.CreationDate)) / (60 * 60 * 24 * 365.25)) AS UserTenureYears,
    0 AS QuestionsPosted,
    0 AS AnswersPosted,
    0 AS TotalPosts,
    0 AS TotalPostScore,
    0 AS TotalPostViews,
    0 AS TotalPostComments,
    0 AS TotalPostFavorites,
    0 AS TotalUserCommentsMade,
    0 AS UpvotesReceivedOnPosts,
    0 AS DownvotesReceivedOnPosts,
    0 AS UpvotesCast,
    0 AS DownvotesCast,
    COALESCE(SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
    COALESCE(SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
    COALESCE(SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
    FALSE AS HasEngagementBadge,
    FALSE AS HasDisciplinedBadge,
    FALSE AS HasPostsClosed,
    FALSE AS HasCommunityOwnedPosts,
    FALSE AS HasMigratedPosts,
    NULL AS AvgScorePerPost,
    NULL AS AvgViewsPerPost,
    NULL AS CommentActivityRatio,
    NULL AS UpToDownvoteRatioReceived,
    NULL AS TopTag1,
    NULL AS TopTag1_Usage,
    NULL AS TopTag1_AvgScore,
    NULL AS TopTag1_PopularityRank,
    NULL AS TopTag1_PerformanceRank,
    NULL AS MostRecentClosedPostId,
    NULL AS MostRecentClosedDate,
    NULL AS MostRecentCloseReason,
    FALSE AS HasSelfLinkedPosts,
    RANK() OVER (ORDER BY U.Reputation DESC) AS OverallUserRank,
    NTILE(10) OVER (ORDER BY U.LastAccessDate ASC) AS UserActivityDecile
FROM Users U
LEFT JOIN Badges B ON U.Id = B.UserId
WHERE
    U.Reputation > 5000 -- High reputation
    AND NOT EXISTS (SELECT 1 FROM Posts P WHERE P.OwnerUserId = U.Id) -- But no posts
    AND NOT EXISTS (SELECT 1 FROM UserCalculatedMetrics active_ucm WHERE active_ucm.UserId = U.Id) -- Exclude from the active set
GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
ORDER BY OverallUserRank ASC, UserTenureYears DESC, Reputation DESC;
