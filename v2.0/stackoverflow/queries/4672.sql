WITH UserPostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AverageScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AverageCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserVoteStats AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) AS BountyStartCount
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgeCount,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadgeCount,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadgeCount
    FROM Badges b
    GROUP BY b.UserId
),
UserContributionSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COALESCE(ups.TotalPosts, 0) AS TotalPosts,
        COALESCE(ups.QuestionCount, 0) AS TotalQuestions,
        COALESCE(ups.AnswerCount, 0) AS TotalAnswers,
        COALESCE(ups.AverageScore, 0.0) AS AvgPostScore,
        COALESCE(ucs.TotalComments, 0) AS TotalComments,
        COALESCE(ucs.AverageCommentScore, 0.0) AS AvgCommentScore,
        COALESCE(uvs.UpVoteCount, 0) AS TotalUpVotes,
        COALESCE(uvs.DownVoteCount, 0) AS TotalDownVotes,
        COALESCE(uvs.BountyStartCount, 0) AS TotalBountyStarts,
        COALESCE(ubs.GoldBadgeCount, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadgeCount, 0) AS SilverBadges,
        COALESCE(ubs.BronzeBadgeCount, 0) AS BronzeBadges,
        CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) / 86400 AS INTEGER) AS DaysSinceCreation,
        CASE
            WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 'Has Website'
            ELSE 'No Website'
        END AS WebsiteStatus,
        LEFT(u.AboutMe, 100) AS AboutMeExcerpt,
        CASE
            WHEN u.LastAccessDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months') THEN 'Inactive'
            ELSE 'Active'
        END AS UserActivityStatus
    FROM Users u
    LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
    LEFT JOIN UserCommentStats ucs ON u.Id = ucs.UserId
    LEFT JOIN UserVoteStats uvs ON u.Id = uvs.UserId
    LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
    WHERE u.Id < 10000
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        ups.TotalPosts,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.AverageScore,
        ucs.TotalComments,
        ucs.AverageCommentScore,
        uvs.UpVoteCount,
        uvs.DownVoteCount,
        uvs.BountyStartCount,
        ubs.GoldBadgeCount,
        ubs.SilverBadgeCount,
        ubs.BronzeBadgeCount,
        u.WebsiteUrl,
        u.AboutMe,
        u.LastAccessDate
),
PostInteraction AS (
    SELECT
        p.Id AS PostId,
        pt.Name AS PostType,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE
            WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) THEN 'Linked Duplicate'
            WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) THEN 'Linked Related'
            ELSE 'Not Linked'
        END AS LinkStatus,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNumPerUser
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId < 10000
)
SELECT
    ucs.UserId,
    ucs.DisplayName,
    ucs.Reputation,
    ucs.UserCreationDate,
    ucs.TotalPosts,
    ucs.TotalQuestions,
    ucs.TotalAnswers,
    ucs.AvgPostScore,
    ucs.TotalComments,
    ucs.AvgCommentScore,
    ucs.TotalUpVotes,
    ucs.TotalDownVotes,
    ucs.GoldBadges,
    ucs.SilverBadges,
    ucs.BronzeBadges,
    ucs.DaysSinceCreation,
    ucs.WebsiteStatus,
    ucs.UserActivityStatus,
    pi_latest.PostType AS LatestPostType,
    pi_latest.Title AS LatestPostTitle,
    pi_latest.Score AS LatestPostScore,
    pi_latest.IsClosed AS LatestPostIsClosed,
    pi_latest.LinkStatus AS LatestPostLinkStatus,
    COALESCE(
        (
            SELECT STRING_AGG(pht.Name, ', ')
            FROM PostHistory ph
            JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
            JOIN Posts p2 ON ph.PostId = p2.Id
            JOIN PostTypes pt ON p2.PostTypeId = pt.Id
            WHERE ph.UserId = ucs.UserId
              AND ph.PostHistoryTypeId IN (4, 5, 6)
              AND ph.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
            GROUP BY ph.UserId
        ),
        'No Recent Edits'
    ) AS RecentEditTypes,
    CASE
        WHEN ucs.TotalPosts > 1000 AND ucs.AvgPostScore > 50 THEN 'High Volume, High Impact User'
        WHEN ucs.TotalQuestions > 500 AND ucs.TotalAnswers > 1000 THEN 'Prolific Questioner & Answerer'
        WHEN ucs.GoldBadges > 5 AND ucs.SilverBadges > 20 THEN 'Highly Decorated User'
        ELSE 'Standard Contributor'
    END AS UserArchetype
FROM UserContributionSummary ucs
LEFT JOIN PostInteraction pi_latest ON ucs.UserId = pi_latest.OwnerUserId AND pi_latest.RowNumPerUser = 1
WHERE ucs.Reputation > 500
  AND ucs.UserActivityStatus = 'Active'
GROUP BY
    ucs.UserId,
    ucs.DisplayName,
    ucs.Reputation,
    ucs.UserCreationDate,
    ucs.TotalPosts,
    ucs.TotalQuestions,
    ucs.TotalAnswers,
    ucs.AvgPostScore,
    ucs.TotalComments,
    ucs.AvgCommentScore,
    ucs.TotalUpVotes,
    ucs.TotalDownVotes,
    ucs.GoldBadges,
    ucs.SilverBadges,
    ucs.BronzeBadges,
    ucs.DaysSinceCreation,
    ucs.WebsiteStatus,
    ucs.UserActivityStatus,
    pi_latest.PostType,
    pi_latest.Title,
    pi_latest.Score,
    pi_latest.IsClosed,
    pi_latest.LinkStatus
ORDER BY ucs.Reputation DESC, ucs.UserCreationDate ASC
LIMIT 100;