-- {"query": "2395.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1598} 
WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        u.DisplayName AS OwnerName,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC NULLS LAST) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RecentRowNum,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalPostsOfType
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
FilteredTags AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        EXISTS (
            SELECT 1 FROM Posts p WHERE p.Tags IS NOT NULL AND POSITION('<' || t.TagName || '>' IN p.Tags) > 0
        ) AS IsUsed
    FROM Tags t
    WHERE t.Count > 1000
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
TopActiveUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
        u.LastAccessDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC NULLS LAST) AS UserRank
    FROM Users u
    LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
    WHERE u.Reputation > 1000
),
PostCommentsCount AS (
    SELECT
        c.PostId,
        COUNT(*) AS CommentCount,
        AVG(LENGTH(c.Text) - LENGTH(REPLACE(c.Text, ' ', '')) + 1) AS AvgCommentWordCount
    FROM Comments c
    GROUP BY c.PostId
),
RecentClosedQuestions AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS CloseDate,
        crt.Name AS CloseReason,
        q.Title,
        q.OwnerUserId,
        u.DisplayName AS OwnerName
    FROM PostHistory ph
    INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id AND pht.Name = 'Post Closed'
    LEFT JOIN CloseReasonTypes crt ON TRY_CAST(ph.Comment AS INT) = crt.Id
    INNER JOIN Posts q ON ph.PostId = q.Id AND q.PostTypeId = 1
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    WHERE ph.CreationDate > NOW() - INTERVAL '90 days'
),
UserActivityWindow AS (
    SELECT
        p.OwnerUserId,
        DATE_TRUNC('month', p.CreationDate) AS ActivityMonth,
        COUNT(*) AS PostsInMonth,
        SUM(p.Score) AS TotalScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY DATE_TRUNC('month', p.CreationDate)) AS MonthSeq
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.PostTypeId IN (1,2)
    GROUP BY p.OwnerUserId, DATE_TRUNC('month', p.CreationDate)
),
ConsecutiveActivityStreaks AS (
    SELECT
        OwnerUserId,
        ActivityMonth,
        PostsInMonth,
        TotalScore,
        MonthSeq,
        ActivityMonth - INTERVAL '1 month' * (MonthSeq - 1) AS StreakMarker
    FROM UserActivityWindow
),
UserStreakLengths AS (
    SELECT
        OwnerUserId,
        COUNT(*) AS ConsecutiveMonthsActive
    FROM (
        SELECT
            OwnerUserId,
            StreakMarker,
            COUNT(*) OVER (PARTITION BY OwnerUserId, StreakMarker) AS StreakLength
        FROM ConsecutiveActivityStreaks
    ) sub
    GROUP BY OwnerUserId, StreakMarker
    HAVING COUNT(*) > 2
)
SELECT
    rp.Id AS PostId,
    rp.PostTypeId,
    rp.Title,
    LEFT(rp.Tags, 100) AS TagSnippet,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.FavoriteCount,
    rp.OwnerUserId,
    rp.OwnerName,
    rp.CreationDate,
    rp.ScoreRank,
    rp.RecentRowNum,
    rp.TotalPostsOfType,
    COALESCE(pc.CommentCount, 0) AS CommentCount,
    COALESCE(pc.AvgCommentWordCount, 0) AS AvgCommentWords,
    tu.DisplayName AS TopUserName,
    tu.Reputation AS TopUserReputation,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    rcq.CloseDate,
    rcq.CloseReason,
    ua.ConsecutiveMonthsActive,
    CASE
        WHEN rp.FavoriteCount IS NULL THEN 'No favorites'
        WHEN rp.FavoriteCount > 100 THEN CONCAT('Popular (', rp.FavoriteCount, ')')
        ELSE 'Normal'
    END AS PopularityStatus,
    CASE
        WHEN rp.Score < 0 THEN 'Negative Score'
        WHEN rp.Score = 0 THEN 'Neutral Score'
        ELSE 'Positive Score'
    END AS ScoreCategory
FROM RankedPosts rp
LEFT JOIN PostCommentsCount pc ON rp.Id = pc.PostId
LEFT JOIN TopActiveUsers tu ON rp.OwnerUserId = tu.Id
LEFT JOIN RecentClosedQuestions rcq ON rp.Id = rcq.PostId
LEFT JOIN (
    SELECT OwnerUserId, MAX(ConsecutiveMonthsActive) AS ConsecutiveMonthsActive
    FROM UserStreakLengths
    GROUP BY OwnerUserId
) ua ON rp.OwnerUserId = ua.OwnerUserId
WHERE rp.PostTypeId = 1
  AND rp.ScoreRank <= 100
  AND (rp.Tags IS NOT NULL AND rp.Tags <> '')
UNION
SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    '' AS TagSnippet,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.OwnerUserId,
    u.DisplayName,
    p.CreationDate,
    NULL,
    NULL,
    NULL,
    0,
    0,
    0,
    NULL,
    NULL,
    NULL,
    'Excluded' AS PopularityStatus,
    'Excluded' AS ScoreCategory
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1
  AND p.ScoreRank > 100
ORDER BY ScoreRank, CreationDate DESC
LIMIT 200;