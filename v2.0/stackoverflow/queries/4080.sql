WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.CommentCount,
        p.AnswerCount,
        p.CreationDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_by_score,
        AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER (PARTITION BY p.PostTypeId) AS avg_score_by_type,
        SUM(p.ViewCount) OVER (PARTITION BY p.PostTypeId) AS total_views_by_type,
        p.LastEditorUserId
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.CreationDate > DATE '2023-01-01'
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT rp.PostId) AS TotalPostsOwned,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsOwned,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersOwned,
        AVG(CAST(rp.Score AS DOUBLE PRECISION)) AS AvgScoreOfOwnedPosts,
        MAX(rp.CreationDate) AS LastPostCreationDate
    FROM Users u
    LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate,
        STRING_AGG(DISTINCT pht.Name, ', ') AS HistoryTypes
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.PostId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.Score,
    rp.ViewCount,
    rp.FavoriteCount,
    rp.CommentCount,
    rp.AnswerCount,
    rp.CreationDate AS PostCreationDate,
    COALESCE(upa.DisplayName, 'Deleted User') AS OwnerDisplayName,
    upa.Reputation AS OwnerReputation,
    CASE
        WHEN rp.Score > (rp.avg_score_by_type * 2) THEN 'High Score'
        WHEN rp.Score < (rp.avg_score_by_type / 2) THEN 'Low Score'
        ELSE 'Average Score'
    END AS ScoreCategory,
    CASE
        WHEN rp.rn_by_score <= 10 THEN 'Top 10 by Rank'
        ELSE 'Not Top 10'
    END AS PopularityRank,
    COALESCE(phs.EditCount, 0) AS PostEditCount,
    phs.LastEditDate,
    phs.HistoryTypes,
    CASE
        WHEN rp.OwnerUserId IS NOT NULL AND rp.OwnerUserId = COALESCE(rp.LastEditorUserId, rp.OwnerUserId) THEN 'Original Owner Last Editor'
        WHEN rp.OwnerUserId IS NOT NULL THEN 'Different Last Editor'
        ELSE 'Community/Deleted Owner'
    END AS EditorStatus,
    (rp.ViewCount + rp.Score * 10 + rp.FavoriteCount * 5) AS WeightedEngagement,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 3) THEN 'Is Duplicate Link'
        ELSE 'Not A Duplicate Link'
    END AS DuplicateLinkStatus,
    LAG(rp.Score, 1, 0) OVER (ORDER BY rp.CreationDate) AS PreviousPostScore
FROM RankedPosts rp
LEFT JOIN UserPostActivity upa ON rp.OwnerUserId = upa.UserId
LEFT JOIN PostHistorySummary phs ON rp.PostId = phs.PostId
WHERE rp.rn_by_score <= 100
ORDER BY rp.PostTypeId, rp.rn_by_score;