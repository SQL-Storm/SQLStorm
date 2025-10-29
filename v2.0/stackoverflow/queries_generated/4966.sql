-- {"query": "4966.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1039} 
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
        p.CommentCount,
        p.FavoriteCount,
        p.AnswerCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) as rn_by_type,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) as avg_score_by_type,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) as prev_day_score,
        SUM(p.ViewCount) OVER (ORDER BY p.CreationDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) as weekly_view_count_sum,
        COUNT(c.Id) OVER (PARTITION BY p.Id) as comment_count_for_post
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
),
PostHistoryAnalysis AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS body_edit_count,
        MAX(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.CreationDate ELSE NULL END) AS last_title_edit_date,
        COUNT(DISTINCT ph.UserId) AS distinct_editors
    FROM PostHistory ph
    WHERE ph.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
    GROUP BY ph.PostId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.Score,
    rp.ViewCount,
    rp.comment_count_for_post,
    rp.weekly_view_count_sum,
    CASE
        WHEN rp.rn_by_type <= 10 THEN 'Top_Newest_By_Type'
        WHEN rp.Score > rp.avg_score_by_type * 1.5 THEN 'Above_Average_Score'
        WHEN rp.prev_day_score > rp.Score THEN 'Score_Decreased'
        ELSE 'Regular'
    END AS performance_category,
    pha.body_edit_count,
    pha.distinct_editors,
    DATEDIFF(day, rp.PostCreationDate, COALESCE(rp.ClosedDate, GETDATE())) AS days_open_or_closed,
    UPPER(rp.OwnerDisplayName) AS upper_owner_name,
    CASE WHEN rp.FavoriteCount IS NULL OR rp.FavoriteCount = 0 THEN 'Not_Favorited' ELSE 'Favorited' END AS favorite_status,
    CONCAT(rp.Score, '-', rp.ViewCount) AS score_view_concat
FROM RankedPosts rp
LEFT JOIN PostHistoryAnalysis pha ON rp.PostId = pha.PostId
WHERE rp.Score > 0
UNION
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.Score,
    rp.ViewCount,
    rp.comment_count_for_post,
    rp.weekly_view_count_sum,
    'Low_Activity' AS performance_category,
    pha.body_edit_count,
    pha.distinct_editors,
    DATEDIFF(day, rp.PostCreationDate, COALESCE(rp.ClosedDate, GETDATE())) AS days_open_or_closed,
    UPPER(rp.OwnerDisplayName) AS upper_owner_name,
    CASE WHEN rp.FavoriteCount IS NULL OR rp.FavoriteCount = 0 THEN 'Not_Favorited' ELSE 'Favorited' END AS favorite_status,
    CONCAT(rp.Score, '-', rp.ViewCount) AS score_view_concat
FROM RankedPosts rp
LEFT JOIN PostHistoryAnalysis pha ON rp.PostId = pha.PostId
WHERE rp.Score <= 0 AND rp.ViewCount < 100;