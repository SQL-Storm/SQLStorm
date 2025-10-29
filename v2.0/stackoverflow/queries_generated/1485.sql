-- {"query": "1485.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2936} 

WITH UserEngagementMetrics AS (
    SELECT
        u.Id AS UserId,
        COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS TotalCommentsMade,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven, -- VoteType 2 is UpMod
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven, -- VoteType 3 is DownMod
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.CreationDate) AS LastPostDate,
        -- Calculate days active posting only if there are posts
        CASE WHEN COUNT(p.Id) > 0 THEN EXTRACT(EPOCH FROM (MAX(p.CreationDate) - MIN(p.CreationDate))) / 86400.0 ELSE 0.0 END AS DaysActivePosting
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
ModeratedPostSummary AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS ClosedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS ReopenedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment ~ '^[0-9]+$' THEN crt.Name END) AS CloseReasonName, -- Check if comment is numeric before casting
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN 1 ELSE 0 END) AS ModerationEventCount
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND ph.Comment ~ '^[0-9]+$' AND crt.Id = CAST(ph.Comment AS int)
    WHERE p.PostTypeId = 1 -- Only questions for moderation analysis
    GROUP BY p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount
),
PostTagAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        -- Handle potential empty tags or tags without content inside <>
        CASE
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 AND SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2) <> ''
            THEN UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'))
            ELSE NULL
        END AS TagName,
        p.Score,
        p.ViewCount
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
),
UserTagPerformance AS (
    SELECT
        OwnerUserId AS UserId,
        TagName,
        COUNT(PostId) AS TagPostCount,
        AVG(Score) AS AvgTagScore,
        SUM(ViewCount) AS TotalTagViews,
        RANK() OVER (PARTITION BY OwnerUserId ORDER BY COUNT(PostId) DESC, AVG(Score) DESC) AS TagRankByUser
    FROM PostTagAnalysis
    WHERE TagName IS NOT NULL
    GROUP BY OwnerUserId, TagName
),
UserBadgeSummary AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(Id) AS TotalBadges,
        MAX(Date) AS LatestBadgeDate
    FROM Badges
    GROUP BY UserId
),
UsersWithHighRepAndActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        'High Reputation & Activity' AS UserCategory,
        uem.TotalPosts,
        uem.TotalQuestions,
        uem.TotalAnswers,
        uem.TotalCommentsMade,
        uem.TotalPostScore
    FROM Users u
    JOIN UserEngagementMetrics uem ON u.Id = uem.UserId
    WHERE u.Reputation > 5000 AND uem.TotalPosts > 100 AND uem.TotalAnswers > 50
),
UsersWithSignificantModerationEvents AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        'Moderation Impact' AS UserCategory,
        uem.TotalPosts,
        uem.TotalQuestions,
        uem.TotalAnswers,
        uem.TotalCommentsMade,
        SUM(mps.ModerationEventCount) AS TotalModeratedPostsEvents
    FROM Users u
    JOIN UserEngagementMetrics uem ON u.Id = uem.UserId
    JOIN ModeratedPostSummary mps ON u.Id = mps.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, uem.TotalPosts, uem.TotalQuestions, uem.TotalAnswers, uem.TotalCommentsMade
    HAVING SUM(mps.ModerationEventCount) > 10
),
UsersWithGoldBadgesOrHighFavs AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        'Gold Badges or High Favorites' AS UserCategory,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoriteCountsOnPosts
    FROM Users u
    LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, COALESCE(ubs.GoldBadges, 0)
    HAVING COALESCE(ubs.GoldBadges, 0) > 0 OR SUM(COALESCE(p.FavoriteCount, 0)) > 50
)
SELECT
    final_users.UserId,
    final_users.DisplayName,
    final_users.UserCategory,
    final_users.Reputation,
    uem.TotalPosts,
    uem.TotalQuestions,
    uem.TotalAnswers,
    uem.TotalCommentsMade,
    uem.TotalPostScore,
    uem.TotalPostViews,
    uem.TotalUpvotesGiven,
    uem.TotalDownvotesGiven,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = final_users.UserId) AND pl.LinkTypeId = 1) AS TotalLinkedPostsByThisUser,
    (
        SELECT COUNT(p_inner.Id)
        FROM Posts p_inner
        WHERE p_inner.OwnerUserId = final_users.UserId
          AND p_inner.PostTypeId = 1 -- Only consider questions for this specific check
          AND EXISTS (
                SELECT 1
                FROM Comments c_inner
                WHERE c_inner.PostId = p_inner.Id
                  AND c_inner.UserId IS NOT NULL -- Comment must have a registered user
                  AND c_inner.UserId <> p_inner.OwnerUserId -- Commenter must be different from post owner
                  AND c_inner.CreationDate <= p_inner.CreationDate + INTERVAL '1 hour' -- Comment within first hour
                ORDER BY c_inner.CreationDate ASC
                LIMIT 1
            )
    ) AS QuestionsWithEarlyExternalComment,
    COALESCE(MAX(CASE WHEN utp.TagRankByUser = 1 THEN utp.TagName END), 'N/A') AS MostFrequentTag,
    COALESCE(MAX(CASE WHEN utp.TagRankByUser = 1 THEN utp.AvgTagScore END), 0.0) AS AvgScoreOnMostFrequentTag,
    MAX(CASE WHEN mps.PostId IS NOT NULL THEN 'Yes' ELSE 'No' END) AS HasModeratedPosts,
    SUM(COALESCE(mps.ModerationEventCount, 0)) AS SumModerationEventsOnUserPosts,
    AVG(CASE WHEN mps.ClosedDate IS NOT NULL AND mps.ReopenedDate IS NOT NULL THEN EXTRACT(EPOCH FROM (mps.ReopenedDate - mps.ClosedDate)) / 3600.0 ELSE NULL END) AS AvgHoursClosedBeforeReopen,
    (uem.TotalPostScore * COALESCE(ubs.GoldBadges, 0)) + (uem.TotalUpvotesGiven * 0.5) + (uem.Reputation / 1000.0) AS CompositeInfluenceScore,
    RANK() OVER (ORDER BY (uem.TotalPostScore * COALESCE(ubs.GoldBadges, 0)) + (uem.TotalUpvotesGiven * 0.5) + (uem.Reputation / 1000.0) DESC) AS OverallInfluenceRank,
    (uem.TotalQuestions * 1.0 / NULLIF(uem.TotalPosts, 0)) AS QuestionRatio,
    UPPER(LEFT(COALESCE(final_users.Location, 'UNKNOWN'), 5)) AS LocationPrefix,
    NULLIF(uem.TotalUpvotesGiven, 0) * 1.0 / NULLIF(uem.TotalDownvotesGiven, 0) AS UpvoteToDownvoteRatioGivenByUser
FROM (
    SELECT UserId, DisplayName, Reputation, Location, UserCategory, TotalPosts, TotalQuestions, TotalAnswers, TotalCommentsMade, TotalPostScore FROM UsersWithHighRepAndActivity
    UNION ALL
    SELECT UserId, DisplayName, Reputation, Location, UserCategory, TotalPosts, TotalQuestions, TotalAnswers, TotalCommentsMade, TotalPostScore FROM UsersWithSignificantModerationEvents
    UNION ALL
    SELECT UserId, DisplayName, Reputation, Location, UserCategory, NULL, NULL, NULL, NULL, NULL FROM UsersWithGoldBadgesOrHighFavs
) AS final_users
LEFT JOIN UserEngagementMetrics uem ON final_users.UserId = uem.UserId
LEFT JOIN UserBadgeSummary ubs ON final_users.UserId = ubs.UserId
LEFT JOIN ModeratedPostSummary mps ON final_users.UserId = mps.OwnerUserId
LEFT JOIN UserTagPerformance utp ON final_users.UserId = utp.UserId AND utp.TagRankByUser = 1
GROUP BY
    final_users.UserId, final_users.DisplayName, final_users.UserCategory, final_users.Reputation,
    uem.TotalPosts, uem.TotalQuestions, uem.TotalAnswers, uem.TotalCommentsMade, uem.TotalPostScore,
    uem.TotalPostViews, uem.TotalUpvotesGiven, uem.TotalDownvotesGiven,
    ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, final_users.Location
ORDER BY OverallInfluenceRank ASC, final_users.Reputation DESC
LIMIT 500;
