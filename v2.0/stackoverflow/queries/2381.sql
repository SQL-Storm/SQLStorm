WITH RECURSIVE RecursiveTaggedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        1 AS Depth
    FROM Posts p
    WHERE p.Tags LIKE '%<sql>%'
      AND p.PostTypeId = 1
    UNION ALL
    SELECT
        pl.RelatedPostId,
        p2.PostTypeId,
        p2.CreationDate,
        p2.OwnerUserId,
        p2.Score,
        p2.ViewCount,
        p2.Tags,
        rt.Depth + 1
    FROM PostLinks pl
    JOIN RecursiveTaggedPosts rt ON pl.PostId = rt.Id
    JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    WHERE pl.LinkTypeId = 1
      AND rt.Depth < 3
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
PostVotesAgg AS (
    SELECT
        v.PostId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotes,
        COUNT(*) AS TotalVotes
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.PostId
),
PostCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        COUNT(*) AS CloseVotesCount,
        MIN(ph.CreationDate) AS FirstCloseVoteDate
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON CAST(ph.Comment AS integer) = crt.Id AND ph.PostHistoryTypeId = 10
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        COUNT(c.Id) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativePosts,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId IN (1, 2)
),
FilteredTopPosts AS (
    SELECT ua.UserId, ua.PostId, ua.Score, ua.ViewCount, ua.RankByScore, ua.CreationDate
    FROM UserActivityWindow ua
    WHERE ua.RankByScore <= 5
      AND ua.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '180 days'
),
CombinedResults AS (
    SELECT
        rt.Id AS PostId,
        rt.Tags,
        rt.Score,
        rt.ViewCount,
        u.Id AS OwnerUserId,
        COALESCE(ub.TotalBadges, 0) AS TotalBadges,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        pv.UpVotes, pv.DownVotes, pv.TotalVotes,
        COALESCE(pcr.CloseReason, 'Not Closed') AS CloseReason,
        COALESCE(pcr.CloseVotesCount, 0) AS CloseVotesCount,
        COALESCE(pcr.FirstCloseVoteDate, TIMESTAMP '1900-01-01') AS FirstCloseVoteDate,
        ftp.Score AS TopAnswerScore,
        ftp.ViewCount AS TopAnswerViewCount,
        ftp.CreationDate AS TopAnswerDate,
        rt.Depth
    FROM RecursiveTaggedPosts rt
    LEFT JOIN Users u ON rt.OwnerUserId = u.Id
    LEFT JOIN UserBadgeSummary ub ON u.Id = ub.UserId
    LEFT JOIN PostVotesAgg pv ON rt.Id = pv.PostId
    LEFT JOIN (
        SELECT DISTINCT ON (ParentId) ParentId, Score, ViewCount, CreationDate
        FROM Posts
        WHERE PostTypeId = 2
        ORDER BY ParentId, Score DESC, ViewCount DESC
    ) ftp ON rt.Id = ftp.ParentId
    LEFT JOIN PostCloseReasons pcr ON rt.Id = pcr.PostId AND pcr.CloseVotesCount = (
        SELECT MAX(CloseVotesCount) FROM PostCloseReasons WHERE PostId = rt.Id
    )
    WHERE rt.Depth = 1
)
SELECT
    cr.PostId,
    cr.Tags,
    cr.Score,
    cr.ViewCount,
    cr.OwnerUserId,
    cr.TotalBadges,
    cr.GoldBadges,
    cr.SilverBadges,
    cr.BronzeBadges,
    cr.UpVotes,
    cr.DownVotes,
    cr.TotalVotes,
    cr.CloseReason,
    cr.CloseVotesCount,
    cr.FirstCloseVoteDate,
    cr.TopAnswerScore,
    cr.TopAnswerViewCount,
    cr.TopAnswerDate,
    COALESCE(ua.AvgPostScore, 0) AS OwnerAvgPostScore,
    (LENGTH(COALESCE(cr.Tags, '')) - LENGTH(REPLACE(COALESCE(cr.Tags, ''), '><', '')) + 1) AS TagCount,
    CASE
        WHEN cr.Score > 100 THEN 'High Score'
        WHEN cr.Score BETWEEN 50 AND 100 THEN 'Medium Score'
        ELSE 'Low Score'
    END AS ScoreCategory,
    SUBSTRING(cr.Tags FROM '<([^<>]+)>') AS FirstTagExtracted,
    (SELECT COUNT(DISTINCT v.UserId) FROM Votes v WHERE v.PostId = cr.PostId AND v.UserId IS NOT NULL) AS UniqueVotersCount,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = cr.OwnerUserId AND p.CreationDate BETWEEN cr.FirstCloseVoteDate - INTERVAL '30 days' AND cr.FirstCloseVoteDate + INTERVAL '30 days') AS AvgScoreAroundClose,
    ROW_NUMBER() OVER (PARTITION BY cr.OwnerUserId ORDER BY cr.Score DESC) AS RankWithinUser
FROM CombinedResults cr
LEFT JOIN (
    SELECT ua.UserId, AVG(ua.AvgPostScore) AS AvgPostScore
    FROM UserActivityWindow ua
    GROUP BY ua.UserId
) ua ON cr.OwnerUserId = ua.UserId
ORDER BY cr.Score DESC, cr.ViewCount DESC, cr.PostId
LIMIT 100;