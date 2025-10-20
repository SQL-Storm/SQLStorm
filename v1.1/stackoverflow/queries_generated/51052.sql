-- {"query": "51052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 827} 

WITH 
monthly_posts AS (
    SELECT 
        DATE_TRUNC('month', p.CreationDate) AS month,
        u.Id AS user_id,
        COUNT(*) AS post_count,
        AVG(p.Score) AS avg_score,
        SUM(COALESCE(p.ViewCount, 0)) AS total_views,
        u.Reputation AS user_reputation
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.CreationDate >= NOW() - INTERVAL '5 years'
    GROUP BY month, u.Id, u.Reputation
),
user_badges AS (
    SELECT 
        b.UserId,
        b.Date,
        DATE_TRUNC('month', b.Date) AS month,
        COUNT(*) AS badge_count,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS has_gold
    FROM Badges b
    GROUP BY b.UserId, b.Date, month
),
monthly_stats AS (
    SELECT 
        mp.month,
        mp.user_id,
        mp.post_count,
        mp.avg_score,
        mp.total_views,
        mp.user_reputation,
        COALESCE(ub.badge_count, 0) AS badge_count,
        COALESCE(ub.has_gold, 0) AS has_gold,
        ROW_NUMBER() OVER (PARTITION BY mp.month ORDER BY mp.post_count DESC, mp.total_views DESC) AS activity_rank
    FROM monthly_posts mp
    LEFT JOIN user_badges ub ON mp.user_id = ub.UserId AND mp.month = ub.month
),
top_contributors AS (
    SELECT 
        month,
        SUM(post_count) AS total_posts,
        COUNT(DISTINCT user_id) AS active_users,
        AVG(avg_score) AS avg_question_score,
        SUM(total_views) AS total_site_views,
        AVG(badge_count) AS avg_badges,
        SUM(has_gold) AS total_gold_badges,
        COUNT(CASE WHEN activity_rank <= 10 THEN 1 END) AS top_10_contributors
    FROM monthly_stats
    GROUP BY month
),
monthly_trends AS (
    SELECT 
        tc.month,
        tc.total_posts,
        tc.active_users,
        tc.avg_question_score,
        tc.total_site_views,
        tc.avg_badges,
        tc.total_gold_badges,
        tc.top_10_contributors,
        LAG(tc.total_posts) OVER (ORDER BY tc.month) AS prev_month_posts,
        (tc.total_posts - LAG(tc.total_posts) OVER (ORDER BY tc.month)) * 100.0 / NULLIF(LAG(tc.total_posts) OVER (ORDER BY tc.month), 0) AS post_growth_pct,
        AVG(tc.total_posts) OVER (ORDER BY tc.month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS moving_avg_posts
    FROM top_contributors tc
    WHERE tc.month >= (SELECT MIN(month) FROM top_contributors) + INTERVAL '3 months'
)
SELECT 
    mt.month,
    mt.total_posts,
    ROUND(mt.post_growth_pct, 2) AS post_growth_percentage,
    ROUND(mt.moving_avg_posts, 0) AS three_month_moving_average,
    mt.active_users,
    ROUND(mt.avg_question_score, 2) AS average_question_score,
    ROUND(mt.total_site_views::numeric / NULLIF(mt.total_posts, 0), 0) AS views_per_question,
    ROUND(mt.avg_badges, 1) AS average_badges_per_user,
    mt.total_gold_badges,
    mt.top_10_contributors,
    -- Calculate engagement ratio
    ROUND(
        (mt.total_site_views::numeric / NULLIF(
            GREATEST(mt.total_posts, 1) * 
            (mt.avg_question_score + 1),  -- Avoid division by zero and account for score
            1
        )), 2
    ) AS engagement_ratio
FROM monthly_trends mt
ORDER BY mt.month DESC
LIMIT 24;
