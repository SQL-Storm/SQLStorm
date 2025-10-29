-- {"query": "4343.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1110} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn_score,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS avg_score_per_type,
        SUM(p.ViewCount) OVER (PARTITION BY p.PostTypeId) AS total_views_per_type,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AnswerCount > 10 THEN 'High Answer Count'
            WHEN p.FavoriteCount > 50 THEN 'Popular'
            ELSE 'Standard'
        END AS PostStatusCategory,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS previous_post_score,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS next_post_score
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= '2023-01-01'
),
PostComments AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCountPerPost,
        SUM(c.Score) AS TotalCommentScore,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments AS c
    GROUP BY c.PostId
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS PostCountByUser,
        SUM(p.Score) AS TotalScoreByUser,
        AVG(p.Score) AS AvgScoreByUser,
        MAX(p.CreationDate) AS LastPostCreationDate
    FROM Posts AS p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount AS PostHistoryCount,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.PostStatusCategory,
    rp.rn_score,
    rp.avg_score_per_type,
    rp.total_views_per_type,
    pc.CommentCountPerPost,
    pc.TotalCommentScore,
    pc.AvgCommentScore,
    pc.LastCommentDate,
    upa.PostCountByUser,
    upa.TotalScoreByUser,
    upa.AvgScoreByUser,
    upa.LastPostCreationDate,
    CASE
        WHEN rp.OwnerUserId IS NULL THEN 'Community'
        WHEN rp.OwnerDisplayName LIKE '%[deleted]%' THEN 'Deleted User'
        WHEN rp.Score > rp.avg_score_per_type * 1.5 THEN 'Above Average Score'
        WHEN rp.ViewCount > rp.total_views_per_type / 1000.0 THEN 'Highly Viewed'
        WHEN rp.previous_post_score IS NOT NULL AND rp.Score > rp.previous_post_score AND rp.next_post_score IS NOT NULL AND rp.Score > rp.next_post_score THEN 'Local Max Score'
        ELSE 'Standard User Activity'
    END AS UserPostPerformanceIndicator,
    CONCAT(COALESCE(rp.OwnerDisplayName, 'N/A'), ' (', COALESCE(CAST(rp.OwnerUserId AS VARCHAR), 'N/A'), ')') AS OwnerInfo,
    (rp.Score * 1.2) + (rp.ViewCount * 0.05) - (rp.CommentCount * 0.1) AS PerformanceMetric,
    CASE WHEN rp.ClosedDate IS NULL THEN 'Open' ELSE 'Closed' END AS PostOpenStatus
FROM RankedPosts AS rp
LEFT JOIN PostComments AS pc ON rp.PostId = pc.PostId
LEFT JOIN UserPostActivity AS upa ON rp.OwnerUserId = upa.OwnerUserId
WHERE rp.rn_score <= 50
AND rp.PostTypeId = 1 -- Focusing on Questions for this example
AND (rp.OwnerUserId IS NULL OR rp.Score > 0 OR rp.ViewCount > 100)
ORDER BY rp.PostTypeId, rp.rn_score;