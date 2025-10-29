WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore,
        AVG(CAST(p.CommentCount AS DOUBLE PRECISION)) OVER (PARTITION BY p.OwnerUserId) AS AvgUserCommentCount,
        SUM(p.ViewCount) OVER (PARTITION BY p.OwnerUserId) AS TotalUserViewCount,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.FavoriteCount > 100 THEN 'Popular'
            WHEN p.Score > 50 THEN 'HighScore'
            ELSE 'Regular'
        END AS PostCategory
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
UserPostStats AS (
    SELECT
        rp.OwnerUserId,
        COUNT(rp.PostId) AS TotalPosts,
        SUM(rp.PostScore) AS TotalScore,
        AVG(CAST(rp.PostScore AS DOUBLE PRECISION)) AS AvgScore,
        MAX(rp.PostScore) AS MaxScore,
        MIN(rp.PostScore) AS MinScore,
        SUM(rp.AnswerCount) AS TotalAnswers,
        SUM(rp.CommentCount) AS TotalComments,
        SUM(rp.FavoriteCount) AS TotalFavorites,
        SUM(CASE WHEN rp.PostCategory = 'Closed' THEN 1 ELSE 0 END) AS ClosedPosts,
        SUM(CASE WHEN rp.PostCategory = 'Popular' THEN 1 ELSE 0 END) AS PopularPosts,
        SUM(CASE WHEN rp.PostCategory = 'HighScore' THEN 1 ELSE 0 END) AS HighScorePosts,
        COUNT(CASE WHEN rp.PostRank = 1 THEN 1 END) AS FirstPostCount,
        COUNT(CASE WHEN rp.PostRank = (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = rp.OwnerUserId AND p2.PostTypeId = 1) THEN 1 END) AS LastPostCount,
        AVG(rp.AvgUserCommentCount) AS AvgOfAvgUserCommentCount
    FROM RankedPosts rp
    GROUP BY rp.OwnerUserId
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        STRING_AGG(b.Name, ', ') AS AllBadgeNames
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COALESCE(ups.TotalPosts, 0) AS UserTotalPosts,
    COALESCE(ups.TotalScore, 0) AS UserTotalScore,
    COALESCE(ups.AvgScore, 0.0) AS UserAvgScore,
    COALESCE(ups.MaxScore, 0) AS UserMaxScore,
    COALESCE(ups.MinScore, 0) AS UserMinScore,
    COALESCE(ups.TotalAnswers, 0) AS UserTotalAnswers,
    COALESCE(ups.TotalComments, 0) AS UserTotalComments,
    COALESCE(ups.TotalFavorites, 0) AS UserTotalFavorites,
    COALESCE(ups.ClosedPosts, 0) AS UserClosedPosts,
    COALESCE(ups.PopularPosts, 0) AS UserPopularPosts,
    COALESCE(ups.HighScorePosts, 0) AS UserHighScorePosts,
    COALESCE(ub.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(ub.SilverBadges, 0) AS UserSilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS UserBronzeBadges,
    ub.AllBadgeNames,
    CASE
        WHEN u.UpVotes > u.DownVotes * 2 THEN 'Mostly Positive Votes'
        WHEN u.DownVotes > u.UpVotes * 2 THEN 'Mostly Negative Votes'
        ELSE 'Balanced Votes'
    END AS VoteRatioCategory,
    CASE
        WHEN u.AboutMe IS NULL OR u.AboutMe = '' THEN 'No Bio'
        WHEN CHAR_LENGTH(u.AboutMe) < 200 THEN 'Short Bio'
        ELSE 'Detailed Bio'
    END AS BioLengthCategory,
    CASE
        WHEN POSITION('USA' IN COALESCE(u.Location, '')) > 0 THEN 'USA Based'
        WHEN POSITION('India' IN COALESCE(u.Location, '')) > 0 THEN 'India Based'
        WHEN u.Location IS NOT NULL AND u.Location <> '' THEN 'Other Location'
        ELSE 'Unknown Location'
    END AS LocationCategory,
    LOWER(SUBSTRING(u.DisplayName FROM 1 FOR 1)) AS FirstInitial,
    REPLACE(COALESCE(u.WebsiteUrl, 'NoWebsite'), 'https://', '') AS CleanWebsiteUrl,
    CASE
        WHEN EXISTS (SELECT 1 FROM Badges b2 WHERE b2.UserId = u.Id AND b2.Name LIKE '%Tagger%') THEN 'Has Tagger Badge'
        ELSE 'No Tagger Badge'
    END AS HasTaggerBadge,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 1) AS OutgoingLinks,
    (SELECT COUNT(*) FROM PostLinks pl2 WHERE pl2.RelatedPostId = rp.PostId AND pl2.LinkTypeId = 3) AS IncomingDuplicates
FROM Users u
LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
LEFT JOIN UserBadges ub ON u.Id = ub.UserId
LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId AND rp.PostRank = 1
WHERE u.Id BETWEEN 1000 AND 5000
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    ups.TotalPosts,
    ups.TotalScore,
    ups.AvgScore,
    ups.MaxScore,
    ups.MinScore,
    ups.TotalAnswers,
    ups.TotalComments,
    ups.TotalFavorites,
    ups.ClosedPosts,
    ups.PopularPosts,
    ups.HighScorePosts,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.AllBadgeNames,
    u.UpVotes,
    u.DownVotes,
    u.AboutMe,
    u.Location,
    u.DisplayName, -- needed for SUBSTRING/LOWER
    u.WebsiteUrl,
    u.Id, -- for EXISTS subquery correlation (allowed but included for completeness)
    rp.PostId
ORDER BY u.Reputation DESC
LIMIT 100;