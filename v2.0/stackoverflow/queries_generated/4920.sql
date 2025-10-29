-- {"query": "4920.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1293} 

WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.AnswerCount,
        p.CommentCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) as rn_by_score_desc,
        AVG(CAST(p.Score AS FLOAT)) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as rolling_avg_score,
        LAG(p.ViewCount, 1, 0) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate) as previous_day_views,
        LEAD(p.Score, 1, 0) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate) as next_day_score,
        COUNT(c.Id) OVER(PARTITION BY p.Id) as comment_count_for_post
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate >= '2023-01-01' AND p.OwnerUserId IS NOT NULL
),
UserPostActivity AS (
    SELECT
        rp.OwnerUserId,
        COUNT(rp.Id) AS total_posts,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_count,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_count,
        AVG(rp.Score) AS avg_score_per_user,
        MAX(rp.CreationDate) AS last_post_date
    FROM RankedPosts rp
    GROUP BY rp.OwnerUserId
    HAVING COUNT(rp.Id) > 10
)
SELECT
    rp.Id,
    rp.PostTypeName,
    rp.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.FavoriteCount,
    rp.AnswerCount,
    rp.CommentCount,
    upa.total_posts AS user_total_posts,
    upa.question_count AS user_question_count,
    upa.answer_count AS user_answer_count,
    upa.avg_score_per_user AS user_avg_score,
    CASE
        WHEN rp.Score > 500 THEN 'High Score'
        WHEN rp.Score BETWEEN 100 AND 500 THEN 'Medium Score'
        ELSE 'Low Score'
    END AS score_category,
    CASE
        WHEN rp.rolling_avg_score IS NULL THEN 0
        ELSE ROUND(rp.rolling_avg_score, 2)
    END AS calculated_rolling_avg_score,
    CASE
        WHEN rp.previous_day_views = 0 THEN 'No Previous Views'
        WHEN rp.ViewCount > rp.previous_day_views * 1.5 THEN 'Significant Growth'
        ELSE 'Stable or Minor Growth'
    END AS view_growth_indicator,
    rp.rn_by_score_desc,
    rp.next_day_score,
    rp.comment_count_for_post,
    CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS post_status,
    UPPER(SUBSTRING(COALESCE(rp.PostTypeName, 'UNKNOWN'), 1, 3)) AS type_prefix
FROM RankedPosts rp
LEFT JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN UserPostActivity upa ON rp.OwnerUserId = upa.OwnerUserId
WHERE rp.rn_by_score_desc <= 1000
  AND rp.Score > 0
  AND rp.ViewCount > 100
  AND rp.OwnerUserId <> -1
  AND rp.PostTypeName <> 'TagWiki'
UNION ALL
SELECT
    p.Id,
    pt.Name AS PostTypeName,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.FavoriteCount,
    p.AnswerCount,
    p.CommentCount,
    NULL AS user_total_posts,
    NULL AS user_question_count,
    NULL AS user_answer_count,
    NULL AS user_avg_score,
    'Other' AS score_category,
    NULL AS calculated_rolling_avg_score,
    NULL AS view_growth_indicator,
    NULL AS rn_by_score_desc,
    NULL AS next_day_score,
    NULL AS comment_count_for_post,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS post_status,
    LOWER(SUBSTRING(pt.Name, 1, 3)) AS type_prefix
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.Id NOT IN (SELECT Id FROM RankedPosts)
  AND p.CreationDate >= '2023-01-01'
  AND p.Score < 0
  AND pt.Name LIKE '%e%'
ORDER BY Score DESC, CreationDate DESC
LIMIT 2000;
