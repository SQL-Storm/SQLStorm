WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_score,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS next_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS moving_avg_score,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END AS score_category,
        COALESCE(p.Title, p.Tags) AS title_or_tags,
        CHAR_LENGTH(p.Body) AS body_length,
        EXTRACT(YEAR FROM p.CreationDate) AS year_created,
        EXTRACT(MONTH FROM p.CreationDate) AS month_created
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id AS user_id,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
        AVG(p.Score) AS avg_score,
        MAX(p.Score) AS max_score,
        MIN(p.Score) AS min_score,
        SUM(p.ViewCount) AS total_views,
        COUNT(DISTINCT b.Id) AS badge_count,
        STRING_AGG(DISTINCT b.Name, ', ') AS badges,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Veteran'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Experienced'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Intermediate'
            ELSE 'New'
        END AS user_level
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        rp.Id,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.prev_score,
        rp.next_score,
        rp.moving_avg_score,
        rp.score_category,
        rp.body_length,
        rp.year_created,
        rp.month_created,
        CASE 
            WHEN rp.prev_score > rp.Score THEN 'Decline'
            WHEN rp.next_score > rp.Score THEN 'Increase'
            WHEN rp.prev_score IS NULL THEN 'New'
            ELSE 'Stable'
        END AS trend,
        CAST(EXTRACT(EPOCH FROM (COALESCE(rp.ClosedDate, TIMESTAMP '2024-10-01 12:34:56') - rp.CreationDate)) / 86400 AS INTEGER) AS days_open,
        CASE WHEN rp.AnswerCount > 0 THEN 'Has Answers' ELSE 'No Answers' END AS answer_status,
        CASE 
            WHEN rp.CommentCount > 10 THEN 'Highly Commented'
            WHEN rp.CommentCount > 5 THEN 'Moderately Commented'
            ELSE 'Low Commented'
        END AS comment_level
    FROM RankedPosts rp
    WHERE rp.rn = 1
),
ComplexMetrics AS (
    SELECT 
        pa.Id,
        pa.OwnerUserId,
        pa.Score,
        pa.ViewCount,
        pa.Title,
        pa.Tags,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.trend,
        pa.days_open,
        pa.answer_status,
        pa.comment_level,
        CASE 
            WHEN pa.days_open > 30 AND pa.Score < 10 THEN 'Inactive Low Score'
            WHEN pa.days_open > 30 AND pa.Score >= 10 THEN 'Inactive High Score'
            WHEN pa.days_open <= 30 AND pa.Score < 10 THEN 'Active Low Score'
            ELSE 'Active High Score'
        END AS status_classification,
        ROW_NUMBER() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.Score DESC) AS score_rank_per_user,
        COUNT(*) OVER (PARTITION BY pa.OwnerUserId) AS total_posts_per_user,
        AVG(pa.ViewCount) OVER (PARTITION BY pa.OwnerUserId) AS avg_views_per_user,
        STDDEV(pa.Score) OVER (PARTITION BY pa.OwnerUserId) AS score_stddev_per_user,
        PERCENT_RANK() OVER (ORDER BY pa.Score) AS percentile_score
    FROM PostAnalysis pa
)
SELECT 
    cm.Id,
    cm.OwnerUserId,
    cm.Score,
    cm.ViewCount,
    cm.Title,
    cm.Tags,
    cm.AnswerCount,
    cm.CommentCount,
    cm.FavoriteCount,
    cm.trend,
    cm.days_open,
    cm.answer_status,
    cm.comment_level,
    cm.status_classification,
    cm.score_rank_per_user,
    cm.total_posts_per_user,
    ROUND(CAST(cm.avg_views_per_user AS NUMERIC), 2) AS avg_views_per_user,
    ROUND(CAST(cm.score_stddev_per_user AS NUMERIC), 2) AS score_stddev_per_user,
    ROUND(CAST(cm.percentile_score * 100 AS NUMERIC), 2) AS percentile_score,
    us.user_level,
    us.total_posts,
    us.question_count,
    us.answer_count,
    ROUND(CAST(us.avg_score AS NUMERIC), 2) AS avg_user_score,
    us.badge_count,
    CASE 
        WHEN us.badges IS NOT NULL THEN TRIM(SUBSTRING(us.badges FROM 1 FOR 100)) || '...'
        ELSE 'No Badges'
    END AS truncated_badges,
    CASE 
        WHEN cm.status_classification = 'Active High Score' AND cm.Score > 50 AND cm.AnswerCount > 2 AND cm.CommentCount > 5 THEN 'Prime Performer'
        WHEN cm.status_classification = 'Active High Score' AND cm.Score > 25 AND cm.AnswerCount > 1 THEN 'Active Contributor'
        WHEN cm.status_classification = 'Inactive Low Score' THEN 'Needs Engagement'
        ELSE 'Standard'
    END AS performance_category,
    CASE 
        WHEN cm.Score > (SELECT AVG(x.Score) FROM ComplexMetrics x) 
         AND cm.ViewCount > (SELECT AVG(x.ViewCount) FROM ComplexMetrics x) 
         AND cm.AnswerCount > (SELECT AVG(x.AnswerCount) FROM ComplexMetrics x) 
        THEN 'Above Average'
        ELSE 'Below Average'
    END AS performance_vs_avg,
    'User: ' || cm.OwnerUserId || ' | Score: ' || cm.Score || ' | Views: ' || cm.ViewCount || ' | Status: ' || cm.status_classification AS formatted_output
FROM ComplexMetrics cm
LEFT JOIN UserStats us ON cm.OwnerUserId = us.user_id
WHERE cm.Score IS NOT NULL
  AND cm.ViewCount IS NOT NULL
  AND (cm.days_open IS NULL OR cm.days_open > 0)
  AND cm.OwnerUserId IS NOT NULL
  AND cm.Title IS NOT NULL
  AND cm.trend IS NOT NULL
  AND cm.status_classification IS NOT NULL
  AND cm.score_rank_per_user IS NOT NULL
  AND cm.total_posts_per_user IS NOT NULL
  AND cm.avg_views_per_user IS NOT NULL
  AND cm.percentile_score IS NOT NULL
  AND us.user_level IS NOT NULL
  AND us.total_posts IS NOT NULL
  AND us.question_count IS NOT NULL
  AND us.answer_count IS NOT NULL
  AND us.avg_score IS NOT NULL
  AND us.badge_count IS NOT NULL
ORDER BY 
    cm.Score DESC,
    cm.ViewCount DESC,
    cm.days_open ASC,
    cm.OwnerUserId ASC,
    cm.score_rank_per_user ASC
LIMIT 1000;