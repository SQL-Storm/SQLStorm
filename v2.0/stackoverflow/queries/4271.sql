WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(CAST(p.AnswerCount AS DOUBLE PRECISION)) AS AvgAnswerCount,
        MAX(p.LastActivityDate) AS LatestActivityDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY p.OwnerUserId
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserVoteStats AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoritesGiven
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Views AS TotalViews,
    COALESCE(upa.TotalPosts, 0) AS UserPostCount,
    COALESCE(upa.TotalScore, 0) AS UserPostScore,
    COALESCE(upa.AvgAnswerCount, 0.0) AS AvgAnswersPerPost,
    COALESCE(uca.TotalComments, 0) AS UserCommentCount,
    COALESCE(uca.TotalCommentScore, 0) AS UserCommentScore,
    COALESCE(uvs.UpVotesGiven, 0) AS VotesCastUp,
    COALESCE(uvs.DownVotesGiven, 0) AS VotesCastDown,
    COALESCE(uvs.FavoritesGiven, 0) AS VotesCastFavorite,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 1
    ) AS GoldBadges,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 2
    ) AS SilverBadges,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 3
    ) AS BronzeBadges,
    CASE
        WHEN u.WebsiteUrl IS NULL THEN 'No Website'
        WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
        ELSE 'External Website'
    END AS WebsiteType,
    COALESCE(rpe.rn, 0) AS LastEditRankForUser,
    CASE
        WHEN (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - u.CreationDate) > INTERVAL '365 days' THEN 'Veteran'
        WHEN (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - u.CreationDate) > INTERVAL '90 days' THEN 'Experienced'
        ELSE 'Newcomer'
    END AS UserTenureGroup,
    CASE
        WHEN upa.LatestActivityDate IS NULL THEN 'No Posts'
        WHEN (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - upa.LatestActivityDate) < INTERVAL '7 days' THEN 'Very Recent'
        WHEN (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - upa.LatestActivityDate) < INTERVAL '30 days' THEN 'Recent'
        ELSE 'Inactive'
    END AS PostActivityStatus
FROM Users u
LEFT JOIN UserPostActivity upa ON u.Id = upa.OwnerUserId
LEFT JOIN UserCommentActivity uca ON u.Id = uca.UserId
LEFT JOIN UserVoteStats uvs ON u.Id = uvs.UserId
LEFT JOIN RankedPostEdits rpe ON u.Id = rpe.UserId AND rpe.rn = 1
WHERE u.Id < 100000
ORDER BY u.Reputation DESC, u.Id;