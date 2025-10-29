-- {"query": "1503.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2996}
WITH UserPostContribution AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        SUM(p.Score) AS TotalPostScoreSum,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViewsSum,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount,
        SUM(COALESCE(p.AnswerCount, 0)) AS TotalAnswersReceivedOnQuestions,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoritesReceivedOnQuestions,
        AVG(CAST(p.Score AS NUMERIC)) AS AvgPostScorePerUser,
        AVG(LENGTH(p.Body)) AS AvgPostBodyLength,
        AVG(CASE WHEN p.PostTypeId = 1 THEN LENGTH(p.Title) ELSE NULL END) AS AvgQuestionTitleLength,
        MAX(p.CreationDate) AS LatestPostCreationDate,
        MIN(p.CreationDate) AS EarliestPostCreationDate,
        AVG(
            CASE
                WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
                THEN ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)), '><'), 1)
                ELSE 0
            END
        ) AS AvgTagsPerQuestion
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalCommentsMade,
        SUM(c.Score) AS TotalCommentScore,
        AVG(CAST(c.Score AS NUMERIC)) AS AvgCommentScoreMade,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserVoteSummary AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT v_given.Id) AS TotalVotesGiven,
        SUM(CASE WHEN v_given.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN v_given.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        SUM(CASE WHEN v_given.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesGiven,
        SUM(COALESCE(vr.UpVotesReceived, 0)) AS UpVotesReceived,
        SUM(COALESCE(vr.DownVotesReceived, 0)) AS DownVotesReceived,
        SUM(COALESCE(vr.AcceptedAnswersReceived, 0)) AS AcceptedAnswersForTheirPosts
    FROM Users u
    LEFT JOIN Votes v_given ON u.Id = v_given.UserId
    LEFT JOIN (
        SELECT
            p.OwnerUserId AS UserId,
            COUNT(CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotesReceived,
            COUNT(CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotesReceived,
            COUNT(CASE WHEN v.VoteTypeId = 1 THEN v.Id END) AS AcceptedAnswersReceived
        FROM Posts p
        JOIN Votes v ON p.Id = v.PostId
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ) AS vr ON u.Id = vr.UserId
    GROUP BY u.Id
),
UserBadgeAndEditSummary AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT b.Id) AS TotalBadgesAwarded,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT ph.PostId) AS PostsEditedByMe,
        COUNT(ph.Id) AS TotalEditsMadeByMe
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    GROUP BY u.Id
),
PostLinkEngagement AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId AS OwnerUserId,
        COUNT(pl_out.Id) AS OutgoingLinkCount,
        COUNT(pl_in.Id) AS IncomingLinkCount,
        COUNT(pl_dup.Id) AS DuplicateSourceCount,
        COUNT(pl_isdup.Id) AS IsDuplicateOfCount
    FROM Posts p
    LEFT JOIN PostLinks pl_out ON p.Id = pl_out.PostId AND pl_out.LinkTypeId = 1
    LEFT JOIN PostLinks pl_in ON p.Id = pl_in.RelatedPostId AND pl_in.LinkTypeId = 1
    LEFT JOIN PostLinks pl_dup ON p.Id = pl_dup.PostId AND pl_dup.LinkTypeId = 3
    LEFT JOIN PostLinks pl_isdup ON p.Id = pl_isdup.RelatedPostId AND pl_isdup.LinkTypeId = 3
    GROUP BY p.Id, p.OwnerUserId
),
UserAggregatedLinkMetrics AS (
    SELECT
        ple.OwnerUserId AS UserId,
        SUM(ple.OutgoingLinkCount) AS TotalOutgoingLinksFromPosts,
        SUM(ple.IncomingLinkCount) AS TotalIncomingLinksToPosts,
        SUM(ple.DuplicateSourceCount) AS TotalDuplicateSources,
        SUM(ple.IsDuplicateOfCount) AS TotalIsDuplicateOf
    FROM PostLinkEngagement ple
    WHERE ple.OwnerUserId IS NOT NULL
    GROUP BY ple.OwnerUserId
),
-- Emulate RANGE BETWEEN INTERVAL '30 days' PRECEDING AND INTERVAL '30 days' FOLLOWING
-- by computing a moving average using a window that compares creation dates via a JOINable CTE.
UserCreationDates AS (
    SELECT Id AS UserId, CreationDate
    FROM Users
    WHERE CreationDate IS NOT NULL
)

SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.Views AS ProfileViews,
    COALESCE(ups.TotalPostsCreated, 0) AS TotalPosts,
    COALESCE(ups.TotalPostScoreSum, 0) AS TotalPostScore,
    COALESCE(uca.TotalCommentsMade, 0) AS TotalComments,
    COALESCE(uvs.UpVotesReceived, 0) AS UpVotesOnPosts,
    COALESCE(ubas.GoldBadges, 0) AS GoldBadgesCount,
    COALESCE(ubas.TotalEditsMadeByMe, 0) AS EditsMade,
    COALESCE(ualm.TotalIncomingLinksToPosts, 0) AS LinksToUsersPosts,
    (
        (COALESCE(ups.TotalPostScoreSum, 0) * 0.5) +
        (COALESCE(uca.TotalCommentScore, 0) * 0.2) +
        (COALESCE(uvs.UpVotesReceived, 0) * 0.8) +
        (COALESCE(uvs.AcceptedAnswersForTheirPosts, 0) * 1.5) +
        (COALESCE(ubas.TotalBadgesAwarded, 0) * 0.3) +
        (COALESCE(ualm.TotalIncomingLinksToPosts, 0) * 0.7)
    ) AS EngagementScore,
    EXTRACT(DAY FROM (u.LastAccessDate - u.CreationDate)) AS DaysSinceCreation,
    CASE
        WHEN COALESCE(uvs.DownVotesReceived, 0) > 0 THEN CAST(COALESCE(uvs.UpVotesReceived, 0) AS NUMERIC) / COALESCE(uvs.DownVotesReceived, 0)
        WHEN COALESCE(uvs.UpVotesReceived, 0) > 0 THEN COALESCE(uvs.UpVotesReceived, 0)
        ELSE 0
    END AS UpvoteDownvoteRatioPosts,
    RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC, u.Id) AS RankByReputationInYear,
    -- Approximate moving average over +/-30 days by joining creation dates and averaging values from ups for users within the date window
    (
        SELECT AVG(COALESCE(ups2.AvgPostScorePerUser, 0))
        FROM Users u2
        LEFT JOIN UserPostContribution ups2 ON u2.Id = ups2.UserId
        WHERE u2.CreationDate BETWEEN u.CreationDate - INTERVAL '30 days' AND u.CreationDate + INTERVAL '30 days'
    ) AS AvgPostScoreMovingAvg,
    (
        SELECT p_top.Title
        FROM Posts p_top
        WHERE p_top.OwnerUserId = u.Id AND p_top.PostTypeId = 1 AND p_top.Title IS NOT NULL
        ORDER BY p_top.Score DESC, p_top.CreationDate DESC
        LIMIT 1
    ) AS TopQuestionTitle,
    COALESCE(TRIM(u.Location), 'N/A') || ' | ' || COALESCE(LOWER(u.WebsiteUrl), 'no website') AS UserContactInfo,
    CASE
        WHEN u.Views > 5000 AND COALESCE(ups.TotalPostsCreated, 0) > 100 AND COALESCE(ubas.GoldBadges, 0) > 0 THEN 'High-Impact Prolific Veteran'
        WHEN u.Views > 1000 AND COALESCE(ups.TotalPostsCreated, 0) > 50 THEN 'Active Contributor'
        WHEN u.Reputation > 10000 AND COALESCE(ubas.GoldBadges, 0) > 0 THEN 'Veteran Elite'
        WHEN COALESCE(ups.TotalPostsCreated, 0) > 10 OR COALESCE(uca.TotalCommentsMade, 0) > 20 THEN 'Emerging User'
        ELSE 'Casual User'
    END AS UserSegment,
    CASE WHEN NULLIF(LENGTH(u.AboutMe), 0) IS NOT NULL AND LENGTH(u.AboutMe) > 500 THEN TRUE ELSE FALSE END AS HasElaborateAboutMe
FROM Users u
LEFT JOIN UserPostContribution ups ON u.Id = ups.UserId
LEFT JOIN UserCommentActivity uca ON u.Id = uca.UserId
LEFT JOIN UserVoteSummary uvs ON u.Id = uvs.UserId
LEFT JOIN UserBadgeAndEditSummary ubas ON u.Id = ubas.UserId
LEFT JOIN UserAggregatedLinkMetrics ualm ON u.Id = ualm.UserId
WHERE
    u.Reputation > 1000
    AND u.LastAccessDate >= u.CreationDate + INTERVAL '90 days'
    AND (
        COALESCE(ups.TotalPostsCreated, 0) > 5
        OR COALESCE(uca.TotalCommentsMade, 0) > 10
        OR COALESCE(ubas.TotalBadgesAwarded, 0) > 2
    )
    AND u.DisplayName IS NOT NULL AND LENGTH(TRIM(u.DisplayName)) > 0
    AND (LOWER(COALESCE(u.Location, '')) LIKE '%usa%' OR LOWER(COALESCE(u.Location, '')) LIKE '%india%' OR u.Location IS NULL)
ORDER BY EngagementScore DESC, u.Reputation DESC, u.CreationDate
LIMIT 1000;