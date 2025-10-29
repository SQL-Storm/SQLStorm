-- {"query": "4207.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1051} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        COALESCE(p.FavoriteCount, 0) + COALESCE(p.AnswerCount, 0) AS EngagementScore,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS RankByScore,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextScore,
        SUM(COALESCE(c.Score, 0)) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningCommentScoreSum
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.OwnerUserId IS NOT NULL AND p.Score > 0 AND p.CreationDate > '2023-01-01'
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) AS EditTitleCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS EditBodyCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedDate
    FROM PostHistory ph
    WHERE ph.PostId IN (SELECT PostId FROM RankedPosts)
    GROUP BY ph.PostId
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViewCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IN (SELECT OwnerUserId FROM RankedPosts)
    GROUP BY u.Id
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.Score,
    rp.EngagementScore,
    rp.RankByScore,
    rp.PreviousScore,
    rp.NextScore,
    rp.runningCommentScoreSum,
    COALESCE(phs.EditTitleCount, 0) AS TotalTitleEdits,
    COALESCE(phs.EditBodyCount, 0) AS TotalBodyEdits,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN phs.LastClosedDate IS NOT NULL AND phs.LastClosedDate > rp.PostCreationDate THEN 'Closed Recently'
        ELSE 'Open'
    END AS PostStatus,
    ue.PostCount AS OwnerPostCount,
    ue.AvgPostScore AS OwnerAvgScore,
    ue.TotalViewCount AS OwnerTotalViews,
    ue.BadgeCount AS OwnerBadgeCount,
    ue.BadgeNames AS OwnerBadges,
    CASE
        WHEN rp.Score > 100 AND rp.PostCreationDate < DATE('now', '-1 year') AND rp.PostTypeId = 1 THEN 'HighScoreOldQuestion'
        WHEN rp.Score < 0 THEN 'NegativeScorePost'
        WHEN rp.ViewCount > 10000 AND rp.AnswerCount > 10 THEN 'PopularAnsweredQuestion'
        ELSE 'StandardPost'
    END AS PostCategory
FROM RankedPosts rp
LEFT JOIN PostHistorySummary phs ON rp.PostId = phs.PostId
LEFT JOIN UserEngagement ue ON rp.OwnerUserId = ue.UserId
WHERE rp.RankByScore <= 100 -- Limit to top 100 posts per type by score
ORDER BY rp.PostTypeId, rp.RankByScore;
