-- {"query": "7480.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2303} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as rolling_avg_score,
        NTILE(100) OVER (ORDER BY p.Score) as score_percentile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= '2022-01-01'
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT b.Id) as badge_count,
        MAX(p.CreationDate) as last_post_date,
        MAX(c.CreationDate) as last_comment_date,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'High'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Medium'
            ELSE 'Low'
        END as activity_level,
        CASE 
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
            THEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 1.0 / 
                 NULLIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END), 0)
            ELSE NULL 
        END as answer_to_question_ratio
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2020-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostAnalysis AS (
    SELECT 
        rp.Id as PostId,
        rp.Title,
        rp.Tags,
        rp.Score,
        rp.ViewCount,
        rp.Score - COALESCE(rp.prev_score, 0) as score_change,
        rp.rolling_avg_score,
        rp.score_percentile,
        CASE 
            WHEN rp.Score > 100 THEN 'High'
            WHEN rp.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as score_category,
        CASE 
            WHEN rp.Title LIKE '%[javascript]%' THEN 'JavaScript Focus'
            WHEN rp.Title LIKE '%[python]%' THEN 'Python Focus'
            WHEN rp.Title LIKE '%[java]%' THEN 'Java Focus'
            ELSE 'Other'
        END as topic_focus,
        COALESCE(rp.AnswerCount, 0) as answer_count,
        COALESCE(rp.CommentCount, 0) as comment_count,
        COALESCE(rp.FavoriteCount, 0) as favorite_count,
        CASE 
            WHEN rp.Score > 0 AND rp.ViewCount > 0 THEN (rp.Score * 1.0) / rp.ViewCount
            ELSE NULL 
        END as score_to_view_ratio,
        CASE 
            WHEN rp.Score > 50 AND rp.AnswerCount > 10 THEN 'Popular Question'
            WHEN rp.Score > 20 AND rp.AnswerCount > 2 THEN 'Decent Question'
            ELSE 'Normal Question'
        END as question_popularity
    FROM RankedPosts rp
    WHERE rp.rn <= 25
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as tag_count,
        CASE 
            WHEN t.Count > 1000 THEN 'Very Popular'
            WHEN t.Count > 500 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as popularity_level,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsRequired,
        t.IsModeratorOnly,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'Above Average'
            ELSE 'Below Average'
        END as avg_comparison
    FROM Tags t
    WHERE t.Count > 50
),
ComplexFiltering AS (
    SELECT 
        pa.*,
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.post_count,
        ua.comment_count,
        ua.badge_count,
        ua.activity_level,
        ua.answer_to_question_ratio,
        ta.TagName,
        ta.tag_count,
        ta.popularity_level,
        ta.avg_comparison
    FROM PostAnalysis pa
    INNER JOIN UserActivity ua ON pa.OwnerUserId = ua.UserId
    INNER JOIN (
        SELECT 
            p.Id as PostId,
            t.TagName
        FROM Posts p
        CROSS JOIN unnest(string_to_array(p.Tags, '>')) AS t(TagName)
        WHERE p.Tags IS NOT NULL AND p.Tags != ''
    ) tag_joined ON pa.PostId = tag_joined.PostId
    INNER JOIN TagAnalysis ta ON tag_joined.TagName = ta.TagName
    WHERE pa.Score > 0 
      AND pa.ViewCount > 100
      AND pa.score_change > 10
      AND ua.Reputation > 1000
      AND (ua.activity_level = 'High' OR ua.activity_level = 'Medium')
),
FinalAggregation AS (
    SELECT 
        cf.*,
        COUNT(*) OVER () as total_filtered_posts,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY cf.Score) as median_score,
        SUM(cf.ViewCount) OVER () as total_views,
        AVG(cf.Score) OVER () as avg_score,
        MIN(cf.CreationDate) OVER () as earliest_post_date,
        MAX(cf.CreationDate) OVER () as latest_post_date,
        (SELECT COUNT(*) FROM Tags WHERE Count > 1000) as very_popular_tags,
        (SELECT COUNT(*) FROM Posts WHERE CreationDate >= '2022-01-01' AND PostTypeId = 1) as new_questions_2022,
        (SELECT COUNT(*) FROM Posts WHERE CreationDate >= '2022-01-01' AND PostTypeId = 2) as new_answers_2022,
        CASE 
            WHEN cf.question_popularity = 'Popular Question' THEN 1
            ELSE 0
        END as is_popular_question,
        CASE 
            WHEN cf.score_to_view_ratio > 0.05 THEN 'High Engagement'
            ELSE 'Normal Engagement'
        END as engagement_level,
        CASE 
            WHEN cf.score_change > (SELECT AVG(score_change) FROM ComplexFiltering) THEN 'Above Average Score Increase'
            ELSE 'Below Average Score Increase'
        END as score_increase_level
    FROM ComplexFiltering cf
)
SELECT 
    fa.PostId,
    fa.Title,
    fa.Tags,
    fa.Score,
    fa.ViewCount,
    fa.score_change,
    fa.rolling_avg_score,
    fa.score_percentile,
    fa.score_category,
    fa.topic_focus,
    fa.answer_count,
    fa.comment_count,
    fa.favorite_count,
    fa.score_to_view_ratio,
    fa.question_popularity,
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.post_count,
    fa.comment_count,
    fa.badge_count,
    fa.activity_level,
    fa.answer_to_question_ratio,
    fa.TagName,
    fa.tag_count,
    fa.popularity_level,
    fa.avg_comparison,
    fa.total_filtered_posts,
    fa.median_score,
    fa.total_views,
    fa.avg_score,
    fa.earliest_post_date,
    fa.latest_post_date,
    fa.very_popular_tags,
    fa.new_questions_2022,
    fa.new_answers_2022,
    fa.is_popular_question,
    fa.engagement_level,
    fa.score_increase_level,
    CASE 
        WHEN fa.score_category = 'High' AND fa.engagement_level = 'High Engagement' AND fa.activity_level = 'High' THEN 'Elite Contributor'
        WHEN fa.score_category = 'Medium' AND fa.engagement_level = 'High Engagement' THEN 'Active Contributor'
        WHEN fa.score_category = 'Low' AND fa.engagement_level = 'High Engagement' THEN 'Engaged Beginner'
        ELSE 'Regular Contributor'
    END as contributor_status
FROM FinalAggregation fa
WHERE fa.score_change > 0
  AND fa.TagName IS NOT NULL
  AND fa.Title IS NOT NULL
  AND fa.ViewCount BETWEEN 100 AND 100000
ORDER BY fa.Score DESC, fa.ViewCount DESC
LIMIT 1000
EXCEPT
SELECT 
    fa.PostId,
    fa.Title,
    fa.Tags,
    fa.Score,
    fa.ViewCount,
    fa.score_change,
    fa.rolling_avg_score,
    fa.score_percentile,
    fa.score_category,
    fa.topic_focus,
    fa.answer_count,
    fa.comment_count,
    fa.favorite_count,
    fa.score_to_view_ratio,
    fa.question_popularity,
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.post_count,
    fa.comment_count,
    fa.badge_count,
    fa.activity_level,
    fa.answer_to_question_ratio,
    fa.TagName,
    fa.tag_count,
    fa.popularity_level,
    fa.avg_comparison,
    fa.total_filtered_posts,
    fa.median_score,
    fa.total_views,
    fa.avg_score,
    fa.earliest_post_date,
    fa.latest_post_date,
    fa.very_popular_tags,
    fa.new_questions_2022,
    fa.new_answers_2022,
    fa.is_popular_question,
    fa.engagement_level,
    fa.score_increase_level,
    CASE 
        WHEN fa.score_category = 'High' AND fa.engagement_level = 'High Engagement' AND fa.activity_level = 'High' THEN 'Elite Contributor'
        WHEN fa.score_category = 'Medium' AND fa.engagement_level = 'High Engagement' THEN 'Active Contributor'
        WHEN fa.score_category = 'Low' AND fa.engagement_level = 'High Engagement' THEN 'Engaged Beginner'
        ELSE 'Regular Contributor'
    END as contributor_status
FROM FinalAggregation fa
WHERE fa.score_change < 0
  AND fa.TagName IS NOT NULL
  AND fa.Title IS NOT NULL
  AND fa.ViewCount BETWEEN 100 AND 100000
LIMIT 500;