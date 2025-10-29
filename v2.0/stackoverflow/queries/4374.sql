-- {"query": "4374.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1405}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
CommentAggregations AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS TotalComments,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreComments,
        AVG(c.Score) AS AverageCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS BodyEdits,
        MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.CreationDate END) AS LastBodyEditDate,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) AS TitleEdits,
        MAX(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.CreationDate END) AS LastTitleEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5)
    GROUP BY ph.PostId
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPostsOwned,
        SUM(p.Score) AS TotalScoreOfOwnedPosts,
        AVG(p.Score) AS AvgScoreOfOwnedPosts,
        MAX(p.CreationDate) AS LastPostOwnedDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
TopUsersWithBadges AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(b.Id) > 5
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.OwnerDisplayName,
    ca.TotalComments,
    ca.PositiveScoreComments,
    ca.AverageCommentScore,
    ca.LastCommentDate,
    phs.BodyEdits,
    phs.LastBodyEditDate,
    phs.TitleEdits,
    phs.LastTitleEditDate,
    upa.TotalPostsOwned,
    upa.TotalScoreOfOwnedPosts,
    upa.AvgScoreOfOwnedPosts,
    upa.LastPostOwnedDate,
    COALESCE(tub.BadgeCount, 0) AS UserBadgeCount,
    COALESCE(tub.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(tub.SilverBadges, 0) AS UserSilverBadges,
    COALESCE(tub.BronzeBadges, 0) AS UserBronzeBadges,
    CASE
        WHEN rp.PostScore > 500 AND rp.AnswerCount > 10 THEN 'Highly Engaged Question'
        WHEN rp.PostScore < 0 THEN 'Negative Score Post'
        WHEN ca.AverageCommentScore < 0 AND ca.TotalComments > 5 THEN 'Highly Criticized Post'
        WHEN phs.BodyEdits > 5 THEN 'Frequently Edited Body'
        WHEN rp.PostCreationDate < (cast('2024-10-01' as date) - INTERVAL '1 year') AND rp.AnswerCount = 0 THEN 'Unanswered Old Question'
        ELSE 'Standard Post'
    END AS PostEngagementCategory,
    UPPER(SUBSTRING(rp.Title FROM 1 FOR 3)) AS TitlePrefix,
    rp.PostScore * (COALESCE(rp.AnswerCount, 0) + 1) AS WeightedScore,
    CASE WHEN rp.PostScore > rp.PostViewCount * 0.01 THEN 'High Score per View Ratio' ELSE 'Normal Score per View Ratio' END AS ScoreViewRatioIndicator,
    rp.PostScore + COALESCE(ca.TotalComments, 0) + COALESCE(rp.AnswerCount, 0) AS CompositeActivityScore
FROM RankedPosts rp
LEFT JOIN CommentAggregations ca ON rp.PostId = ca.PostId
LEFT JOIN PostHistorySummary phs ON rp.PostId = phs.PostId
LEFT JOIN UserPostActivity upa ON rp.OwnerUserId = upa.OwnerUserId
LEFT JOIN TopUsersWithBadges tub ON rp.OwnerUserId = tub.UserId
WHERE rp.rn <= 100
  AND rp.PostTypeName IS NOT NULL
  AND (rp.OwnerUserId IS NULL OR rp.OwnerUserId <> -1)
ORDER BY rp.PostCreationDate DESC
LIMIT 500;