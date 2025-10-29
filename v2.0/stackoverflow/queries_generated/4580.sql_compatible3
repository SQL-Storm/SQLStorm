WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) as rn,
        CASE
            WHEN p.Tags LIKE '%<sql>%' THEN 'SQL'
            WHEN p.Tags LIKE '%<performance>%' THEN 'Performance'
            WHEN p.Tags LIKE '%<optimization>%' THEN 'Optimization'
            WHEN p.Tags LIKE '%<query>%' THEN 'Query'
            ELSE 'Other'
        END AS PrimaryTagCategory,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) as PreviousPostScore,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) as NextPostScore,
        COUNT(c.Id) OVER (PARTITION BY p.Id) as CommentCountForPost,
        SUM(v.VoteTypeId) OVER (PARTITION BY p.Id) as TotalVoteValueForPost
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate > DATE '2023-01-01'
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.CreationDate ELSE NULL END) AS LastTitleEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.CreationDate ELSE NULL END) AS LastBodyEditDate,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN ph.Id ELSE NULL END) AS CloseReopenVoteCount
    FROM PostHistory ph
    WHERE ph.PostId IN (SELECT Id FROM Posts WHERE PostTypeId IN (1, 2))
    GROUP BY ph.PostId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.PrimaryTagCategory,
    rp.PreviousPostScore,
    rp.NextPostScore,
    rp.CommentCountForPost,
    rp.TotalVoteValueForPost,
    phs.LastTitleEditDate,
    phs.LastBodyEditDate,
    phs.CloseReopenVoteCount,
    CASE
        WHEN rp.PostScore > (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = rp.PostTypeId) THEN 'Above Average Score'
        WHEN rp.PostScore < (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = rp.PostTypeId) THEN 'Below Average Score'
        ELSE 'Average Score'
    END AS ScoreComparison,
    CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    CAST(rp.OwnerUserId AS VARCHAR) || '-' || CAST(rp.PostId AS VARCHAR) AS CompositeKey,
    CASE WHEN rp.rn <= 5 THEN 'Top 5 Newest for Type' ELSE 'Others' END AS RankCategory,
    rp.PostScore + COALESCE(rp.FavoriteCount, 0) * 2 AS WeightedScore,
    UPPER(COALESCE(rp.OwnerDisplayName, 'Anonymous')) AS CasedOwnerName,
    CASE
        WHEN rp.PostScore > 0 AND rp.PostViewCount > 0 THEN CAST(rp.PostScore AS DOUBLE PRECISION) / rp.PostViewCount
        ELSE 0
    END AS ScoreToViewRatio,
    EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = rp.OwnerUserId AND b.Name LIKE '%Expert%') AS HasExpertBadge,
    COALESCE(rp.AnswerCount, 0) + COALESCE(rp.CommentCount, 0) AS InteractionCount,
    CASE
        WHEN phs.LastTitleEditDate IS NOT NULL AND phs.LastBodyEditDate IS NOT NULL THEN
            (EXTRACT(EPOCH FROM (phs.LastBodyEditDate - phs.LastTitleEditDate)) / 86400.0)
        ELSE NULL
    END AS EditDateDifference,
    COALESCE(rp.PostScore, 0) + COALESCE(rp.AnswerCount, 0) * 5 AS EngagementMetric,
    CASE WHEN rp.PostTypeId = 1 THEN 'Question' WHEN rp.PostTypeId = 2 THEN 'Answer' ELSE 'Other' END AS QuestionOrAnswer,
    rp.PostScore * CASE WHEN rp.OwnerDisplayName = 'Community' THEN 0.5 ELSE 1 END AS CommunityAdjustedScore,
    CASE
        WHEN (rp.PostScore > 100 OR rp.FavoriteCount > 50) AND rp.PostCreationDate < (DATE '2024-10-01' - INTERVAL '1 year') THEN 'High Performing Old Post'
        WHEN rp.PostScore < 0 THEN 'Negative Score Post'
        ELSE 'Standard Post'
    END AS PostPerformanceTier,
    CASE WHEN rp.OwnerUserId IS NULL THEN 'Orphaned' ELSE 'Owned' END AS OwnershipStatus,
    rp.PostScore / (COALESCE(rp.CommentCount, 0) + 1) AS ScorePerComment,
    CAST(EXTRACT(YEAR FROM rp.PostCreationDate) AS VARCHAR) AS PostYear,
    CASE
        WHEN rp.OwnerDisplayName IN ('Community', 'Stack Exchange') THEN TRUE
        ELSE FALSE
    END AS IsCommunityOwned,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rp.PostId OR pl.RelatedPostId = rp.PostId) AS LinkedPostCount,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.rn
FROM RankedPosts rp
LEFT JOIN PostHistorySummary phs ON rp.PostId = phs.PostId
WHERE rp.rn <= 100
GROUP BY
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.PrimaryTagCategory,
    rp.PreviousPostScore,
    rp.NextPostScore,
    rp.CommentCountForPost,
    rp.TotalVoteValueForPost,
    phs.LastTitleEditDate,
    phs.LastBodyEditDate,
    phs.CloseReopenVoteCount,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.rn
ORDER BY rp.PostCreationDate DESC
LIMIT 1000;