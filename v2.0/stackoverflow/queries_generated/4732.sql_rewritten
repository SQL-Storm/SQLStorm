-- {"query": "4732.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1645} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount AS PostViewCount,
        p.Title AS PostTitle,
        p.Tags AS PostTags,
        p.ClosedDate,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        u.Views AS OwnerViews,
        u.UpVotes AS OwnerUpVotes,
        u.DownVotes AS OwnerDownVotes,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) as rn_by_score,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextScore,
        SUM(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningTotalScore
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
CommentAggregations AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCountForPost,
        SUM(c.Score) AS TotalCommentScore,
        AVG(CAST(c.Score AS FLOAT)) AS AverageCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
VoteAggregations AS (
    SELECT
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoriteVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) AS BountyStartCount
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3, 5, 8)
    GROUP BY v.PostId
),
PostHistoryAnalysis AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.CreationDate ELSE NULL END) AS LastTitleEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.CreationDate ELSE NULL END) AS LastBodyEditDate,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN 1 END) AS CloseReopenEventCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS LastCloseReason,
        (SELECT COUNT(*) FROM PostHistory ph2 WHERE ph2.PostId = ph.PostId AND ph2.PostHistoryTypeId = 2) AS InitialBodyRevisions
    FROM PostHistory ph
    GROUP BY ph.PostId
)
SELECT
    rp.PostId,
    rp.PostTitle,
    rp.PostTags,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount,
    rp.CommentCount AS PostDirectCommentCount,
    ca.CommentCountForPost AS TotalComments,
    ca.TotalCommentScore,
    ca.AverageCommentScore,
    va.UpVoteCount,
    va.DownVoteCount,
    va.FavoriteVoteCount,
    va.BountyStartCount,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    rp.OwnerViews,
    rp.OwnerUpVotes,
    rp.OwnerDownVotes,
    rp.rn_by_score,
    rp.PreviousScore,
    rp.NextScore,
    rp.RunningTotalScore,
    pha.LastTitleEditDate,
    pha.LastBodyEditDate,
    pha.CloseReopenEventCount,
    pha.LastCloseReason,
    pha.InitialBodyRevisions,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.OwnerUserId IS NULL THEN 'Community Owned'
        WHEN rp.PostTags LIKE '%<performance-testing>%' THEN 'Performance Tagged'
        WHEN LENGTH(rp.PostTitle) > 80 THEN 'Long Title'
        ELSE 'Standard'
    END AS PostCategory,
    COALESCE(u.DisplayName, 'Deleted User') AS ActualOwnerDisplayName,
    COALESCE(rp.OwnerDisplayName, 'N/A') AS SafeOwnerDisplayName,
    (rp.PostScore * 1.0 / NULLIF(rp.PostViewCount, 0)) AS ScoreToViewRatio,
    DATE_PART('day', AGE(cast('2024-10-01 12:34:56' as timestamp), rp.PostCreationDate)) AS DaysSinceCreation,
    CASE
        WHEN ca.LastCommentDate IS NOT NULL THEN
            CASE
                WHEN DATE_PART('hour', AGE(cast('2024-10-01 12:34:56' as timestamp), ca.LastCommentDate)) < 24 THEN 'Recent Comment'
                ELSE 'Older Comment'
            END
        ELSE 'No Comments'
    END AS CommentRecency,
    CASE
        WHEN rp.PostTags IS NULL THEN 'No Tags'
        WHEN rp.PostTags = '' THEN 'Empty Tags'
        ELSE SUBSTRING(rp.PostTags FROM 2 FOR LENGTH(rp.PostTags) - 2)
    END AS FormattedTags,
    CASE
        WHEN rp.PostScore > 500 THEN 'High Score'
        WHEN rp.PostScore < 0 THEN 'Negative Score'
        ELSE 'Mid Score'
    END AS ScoreBracket,
    CASE
        WHEN rp.PostTags IS NOT NULL AND rp.PostTags LIKE '%<sql>%' AND rp.PostTags LIKE '%<performance>%' THEN 'SQL Performance'
        WHEN rp.PostTags IS NOT NULL AND rp.PostTags LIKE '%<python>%' THEN 'Python Related'
        ELSE 'Other'
    END AS TopicArea
FROM RankedPosts rp
LEFT JOIN CommentAggregations ca ON rp.PostId = ca.PostId
LEFT JOIN VoteAggregations va ON rp.PostId = va.PostId
LEFT JOIN PostHistoryAnalysis pha ON rp.PostId = pha.PostId
LEFT JOIN Users u ON rp.OwnerUserId = u.Id -- Joining again to ensure we get the user even if OwnerUserId was initially NULL in RankedPosts logic due to potential issues
WHERE rp.rn_by_score <= 100 -- Top 100 by score within each post type
  AND rp.PostScore > 0
  AND rp.PostCreationDate > '2023-01-01'
  AND (rp.ClosedDate IS NULL OR rp.ClosedDate > '2023-01-01')
ORDER BY rp.PostTypeId, rp.rn_by_score;