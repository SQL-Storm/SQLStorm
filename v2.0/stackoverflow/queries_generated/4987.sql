-- {"query": "4987.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1615} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.Score > 0 AND p.ViewCount > 1000
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgeCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadgeCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.Score) AS AvgPostScore
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostEditAnalysis AS (
    SELECT
        ph.PostId,
        ph.UserId AS EditorUserId,
        COUNT(DISTINCT ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate,
        ph.PostHistoryTypeId,
        CASE
            WHEN ph.PostHistoryTypeId IN (4, 7) THEN 'Title Edit'
            WHEN ph.PostHistoryTypeId IN (5, 8) THEN 'Body Edit'
            WHEN ph.PostHistoryTypeId IN (6, 9) THEN 'Tags Edit'
            ELSE 'Other Edit'
        END AS EditType,
        SUM(CASE WHEN ph.Comment IS NOT NULL AND ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        SUM(CASE WHEN ph.Comment IS NOT NULL AND ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVoteCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 10, 11)
    GROUP BY ph.PostId, ph.UserId, ph.PostHistoryTypeId
)
SELECT
    rp.Title AS TopPostTitle,
    rp.PostTypeName,
    ue.DisplayName AS TopPostOwner,
    ue.Reputation AS TopPostOwnerReputation,
    ue.GoldBadgeCount,
    ue.SilverBadgeCount,
    ue.BronzeBadgeCount,
    ue.CommentCount AS OwnerCommentCount,
    ue.UpVoteCount AS OwnerUpVoteCount,
    ue.AvgPostScore AS TopPostOwnerAvgScore,
    pe.EditorUserId AS FrequentEditor,
    pe.EditCount AS PostEditCount,
    pe.EditType,
    pe.CloseVoteCount,
    pe.ReopenVoteCount,
    CASE
        WHEN rp.PostScore > 500 AND rp.rn <= 10 THEN 'Highly Scored Question'
        WHEN ue.Reputation > 10000 AND ue.AvgPostScore > 20 THEN 'Reputable Author, High Score Post'
        WHEN pe.EditCount > 15 AND pe.CloseVoteCount > 3 THEN 'Active Editor with Many Close Votes'
        ELSE 'Standard Performance Metric'
    END AS PerformanceCategory,
    CONCAT(rp.PostTypeName, ' - ', rp.Title) AS PostIdentifier,
    ue.DisplayName || ' (' || ue.Reputation || ')' AS UserSummary,
    CASE
        WHEN rp.PostCreationDate < ue.LastPostDate THEN 'Post Older Than Last Activity'
        WHEN rp.PostCreationDate >= ue.LastPostDate THEN 'Post Newer Than Last Activity'
        ELSE 'Unknown Activity Relation'
    END AS ActivityTimeline,
    COALESCE(rp.PostScore, 0) AS SafePostScore,
    rp.PostScore * LENGTH(rp.Title) AS ScoreTitleLengthProduct,
    rp.PostScore + COALESCE(ue.CommentCount, 0) AS CombinedScore,
    CASE WHEN rp.PostScore IS NULL OR ue.Reputation IS NULL OR pe.EditCount IS NULL THEN TRUE ELSE FALSE END AS HasNullMetrics
FROM RankedPosts rp
JOIN UserEngagement ue ON rp.OwnerUserId = ue.UserId
LEFT JOIN PostEditAnalysis pe ON rp.PostId = pe.PostId AND rp.OwnerUserId = pe.EditorUserId
WHERE rp.rn <= 20 AND ue.Reputation > 5000
UNION ALL
SELECT
    rp.Title,
    rp.PostTypeName,
    ue.DisplayName,
    ue.Reputation,
    ue.GoldBadgeCount,
    ue.SilverBadgeCount,
    ue.BronzeBadgeCount,
    ue.CommentCount,
    ue.UpVoteCount,
    ue.AvgPostScore,
    pe.EditorUserId,
    pe.EditCount,
    pe.EditType,
    pe.CloseVoteCount,
    pe.ReopenVoteCount,
    CASE
        WHEN rp.PostScore < 0 AND ue.DownVoteCount > 5 THEN 'Low Scored Post, High Downvotes'
        ELSE 'Negative Performance Indicator'
    END AS PerformanceCategory,
    CONCAT(rp.PostTypeName, ' - ', rp.Title),
    ue.DisplayName || ' (' || ue.Reputation || ')',
    CASE
        WHEN rp.PostCreationDate < ue.LastPostDate THEN 'Post Older Than Last Activity'
        WHEN rp.PostCreationDate >= ue.LastPostDate THEN 'Post Newer Than Last Activity'
        ELSE 'Unknown Activity Relation'
    END AS ActivityTimeline,
    COALESCE(rp.PostScore, 0),
    rp.PostScore * LENGTH(rp.Title),
    rp.PostScore + COALESCE(ue.CommentCount, 0),
    CASE WHEN rp.PostScore IS NULL OR ue.Reputation IS NULL OR pe.EditCount IS NULL THEN TRUE ELSE FALSE END AS HasNullMetrics
FROM RankedPosts rp
JOIN UserEngagement ue ON rp.OwnerUserId = ue.UserId
LEFT JOIN PostEditAnalysis pe ON rp.PostId = pe.PostId AND rp.OwnerUserId = pe.EditorUserId
WHERE rp.PostScore < 0 AND rp.rn <= 10;
