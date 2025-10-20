WITH UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        AVG(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) / 86400.0) AS DaysSinceCreation,
        COALESCE(STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Name), 'No Badges') AS BadgeNames
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
TopQuestionPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserTopQuestions AS (
    SELECT
        tp.OwnerUserId,
        COUNT(*) AS NumTopQuestions,
        AVG(tp.Score) AS AvgTopQuestionScore,
        MAX(tp.Score) AS MaxTopQuestionScore
    FROM TopQuestionPosts tp
    WHERE tp.rn <= 3
    GROUP BY tp.OwnerUserId
),
RecentCommentsPerUser AS (
    SELECT
        c.UserId,
        COUNT(*) AS RecentCommentCount,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        SUM(CASE WHEN LOWER(c.Text) LIKE '%sql%' THEN 1 ELSE 0 END) AS SqlKeywordCount
    FROM Comments c
    WHERE c.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180 days')
    GROUP BY c.UserId
),
UserActivityScore AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COALESCE(uts.TotalBadges, 0) AS TotalBadges,
        COALESCE(uts.GoldBadges, 0) AS GoldBadges,
        COALESCE(uts.SilverBadges, 0) AS SilverBadges,
        COALESCE(uts.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(utq.NumTopQuestions, 0) AS NumTopQuestions,
        COALESCE(utq.AvgTopQuestionScore, 0) AS AvgTopQuestionScore,
        COALESCE(rcp.RecentCommentCount, 0) AS RecentCommentCount,
        COALESCE(rcp.SqlKeywordCount, 0) AS SqlKeywordCount,
        (
            u.Reputation * 0.5 +
            COALESCE(uts.GoldBadges, 0) * 10 +
            COALESCE(uts.SilverBadges, 0) * 5 +
            COALESCE(uts.BronzeBadges, 0) * 2 +
            COALESCE(utq.NumTopQuestions, 0) * 3 +
            COALESCE(utq.AvgTopQuestionScore, 0) * 1.5 +
            COALESCE(rcp.RecentCommentCount, 0) * 0.3 +
            COALESCE(rcp.SqlKeywordCount, 0) * 0.5
        ) AS ActivityScore
    FROM Users u
    LEFT JOIN UserBadgeStats uts ON uts.UserId = u.Id
    LEFT JOIN UserTopQuestions utq ON utq.OwnerUserId = u.Id
    LEFT JOIN RecentCommentsPerUser rcp ON rcp.UserId = u.Id
),
PostScoreWindows AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.CreationDate,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS MovingAvgScore5,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS ScoreRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS PostCountPerUser
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
ComplexPostStats AS (
    SELECT
        psw.OwnerUserId,
        COUNT(*) FILTER (WHERE psw.ScoreRank = 1) AS NumTopScorePosts,
        AVG(psw.MovingAvgScore5) FILTER (WHERE psw.PostCountPerUser >= 5) AS AvgMovingScoreForActiveUsers,
        COUNT(DISTINCT pl.RelatedPostId) AS DistinctLinkedPostsCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicateLinksCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS RegularLinksCount
    FROM PostScoreWindows psw
    LEFT JOIN PostLinks pl ON pl.PostId = psw.Id
    GROUP BY psw.OwnerUserId
),
HighlyActiveUsers AS (
    SELECT
        uas.UserId,
        uas.ActivityScore,
        uas.Reputation,
        bd.BadgeNames,
        cps.NumTopScorePosts,
        cps.AvgMovingScoreForActiveUsers,
        cps.DistinctLinkedPostsCount,
        cps.DuplicateLinksCount,
        cps.RegularLinksCount,
        u.DisplayName,
        u.Location,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes
    FROM UserActivityScore uas
    INNER JOIN Users u ON u.Id = uas.UserId
    LEFT JOIN UserBadgeStats bd ON bd.UserId = uas.UserId
    LEFT JOIN ComplexPostStats cps ON cps.OwnerUserId = uas.UserId
    WHERE uas.ActivityScore > (
        SELECT PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY ActivityScore) FROM UserActivityScore
    )
)
SELECT
    hau.UserId,
    hau.DisplayName,
    hau.Location,
    hau.CreationDate,
    hau.LastAccessDate,
    hau.Reputation,
    hau.Views,
    hau.UpVotes,
    hau.DownVotes,
    hau.BadgeNames,
    hau.NumTopScorePosts,
    COALESCE(ROUND(CAST(hau.AvgMovingScoreForActiveUsers AS NUMERIC), 2), 0) AS AvgMovingScoreForActiveUsers,
    hau.DistinctLinkedPostsCount,
    hau.DuplicateLinksCount,
    hau.RegularLinksCount,
    ROUND(hau.ActivityScore, 2) AS ActivityScore,
    (
        SELECT p.Title
        FROM Posts p
        JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
        WHERE p.OwnerUserId = hau.UserId AND p.PostTypeId = 1
        ORDER BY ph.CreationDate DESC
        FETCH FIRST 1 ROW ONLY
    ) AS MostRecentClosedQuestionTitle,
    (CASE
        WHEN hau.DuplicateLinksCount > 5 THEN 'Prolific duplicator'
        WHEN hau.NumTopScorePosts >= 10 THEN 'Top scorer'
        WHEN hau.ActivityScore > 1000 THEN 'Highly active user'
        ELSE 'Regular contributor'
    END) ||
    ' - Has ' || COALESCE(NULLIF(hau.BadgeNames, ''), 'no badges') AS UserSummary
FROM HighlyActiveUsers hau
ORDER BY hau.ActivityScore DESC, hau.Reputation DESC
FETCH FIRST 50 ROWS ONLY;