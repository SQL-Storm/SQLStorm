-- {"query": "29084.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3425} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        NTILE(100) OVER (ORDER BY p.Score) as score_percentile,
        COALESCE(p.Tags, '') as tags_clean,
        CASE WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN ARRAY_LENGTH(string_to_array(p.Tags, '><'), 1) ELSE 0 END as tag_count
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT b.Id) as badge_count,
        SUM(COALESCE(p.Score, 0)) as total_score,
        AVG(COALESCE(p.Score, 0)) as avg_score,
        MAX(p.CreationDate) as last_post_date,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as activity_rank,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as rep_rank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Highly Popular'
            WHEN t.Count > 500 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Low'
            ELSE 'Very Low'
        END as popularity_level,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as popularity_rank,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) as prev_count,
        (t.Count - LAG(t.Count) OVER (ORDER BY t.Count DESC)) / NULLIF(LAG(t.Count) OVER (ORDER BY t.Count DESC), 0) * 100 as growth_rate_percent
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
),
ComplexPostAnalysis AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.LastActivityDate,
        rp.rn,
        rp.prev_score,
        rp.score_percentile,
        rp.tags_clean,
        rp.tag_count,
        CASE 
            WHEN rp.Score > 1000 THEN 'Virtually Legendary'
            WHEN rp.Score > 500 THEN 'Legendary'
            WHEN rp.Score > 100 THEN 'Highly Respected'
            WHEN rp.Score > 50 THEN 'Respected'
            WHEN rp.Score > 0 THEN 'Known'
            ELSE 'Unknown'
        END as reputation_level,
        COALESCE(
            CASE 
                WHEN rp.PostTypeId = 1 THEN 
                    CASE 
                        WHEN rp.AnswerCount > 0 THEN 'Answered Question'
                        WHEN rp.AnswerCount = 0 THEN 'Unanswered Question'
                    END
                WHEN rp.PostTypeId = 2 THEN 'Answer'
                ELSE 'Other'
            END, 
            'Unknown'
        ) as post_category,
        DATEDIFF('day', rp.CreationDate, CURRENT_TIMESTAMP) as days_since_creation,
        CASE 
            WHEN rp.Score >= 100 AND rp.ViewCount >= 1000 THEN 'Trending'
            WHEN rp.Score >= 50 AND rp.ViewCount >= 500 THEN 'Popular'
            WHEN rp.Score >= 10 AND rp.ViewCount >= 100 THEN 'Notable'
            ELSE 'Regular'
        END as trend_status,
        (rp.Score * 0.7 + rp.ViewCount * 0.3) as combined_metric,
        CASE 
            WHEN rp.TagCount = 0 THEN 'No Tags'
            WHEN rp.TagCount BETWEEN 1 AND 2 THEN 'Few Tags'
            WHEN rp.TagCount BETWEEN 3 AND 5 THEN 'Moderate Tags'
            ELSE 'Many Tags'
        END as tag_density_level,
        CASE 
            WHEN rp.LastActivityDate > DATEADD('day', -7, CURRENT_TIMESTAMP) THEN 'Recently Active'
            WHEN rp.LastActivityDate > DATEADD('day', -30, CURRENT_TIMESTAMP) THEN 'Active Recently'
            WHEN rp.LastActivityDate > DATEADD('day', -90, CURRENT_TIMESTAMP) THEN 'Active'
            ELSE 'Inactive'
        END as activity_status
    FROM RankedPosts rp
    WHERE rp.rn = 1 OR rp.Score > 50
),
CrossJoinAnalysis AS (
    SELECT 
        cpa.Id as post_id,
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.post_count,
        uas.comment_count,
        uas.badge_count,
        uas.total_score,
        cpa.Score as post_score,
        cpa.ViewCount as post_view_count,
        cpa.Title as post_title,
        cpa.Tags as post_tags,
        cpa.AnswerCount as post_answer_count,
        cpa.CommentCount as post_comment_count,
        cpa.FavoriteCount as post_favorite_count,
        cpa.reputation_level,
        cpa.post_category,
        cpa.trend_status,
        cpa.combined_metric,
        cpa.tag_density_level,
        cpa.activity_status,
        'Analysis' as analysis_type,
        CASE 
            WHEN cpa.Score > 500 AND uas.total_score > 5000 THEN 'Elite Contributor'
            WHEN cpa.Score > 100 AND uas.total_score > 1000 THEN 'Experienced Contributor'
            WHEN cpa.Score > 50 THEN 'Active Contributor'
            ELSE 'New Contributor'
        END as contributor_level
    FROM ComplexPostAnalysis cpa
    CROSS JOIN UserActivityStats uas
    WHERE cpa.OwnerUserId = uas.UserId
    AND uas.activity_rank <= 100
    AND cpa.combined_metric > 100
),
FinalAnalysis AS (
    SELECT 
        DISTINCT 
        cja.post_id,
        cja.UserId,
        cja.DisplayName,
        cja.Reputation,
        cja.post_count,
        cja.comment_count,
        cja.badge_count,
        cja.total_score,
        cja.post_score,
        cja.post_view_count,
        cja.post_title,
        cja.post_tags,
        cja.post_answer_count,
        cja.post_comment_count,
        cja.post_favorite_count,
        cja.reputation_level,
        cja.post_category,
        cja.trend_status,
        cja.combined_metric,
        cja.tag_density_level,
        cja.activity_status,
        cja.analysis_type,
        cja.contributor_level,
        DENSE_RANK() OVER (ORDER BY cja.combined_metric DESC) as metric_rank,
        PERCENT_RANK() OVER (ORDER BY cja.combined_metric) as metric_percentile,
        ROUND(SUM(cja.post_score) OVER (PARTITION BY cja.UserId ORDER BY cja.post_score ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2) as cumulative_score,
        AVG(cja.post_score) OVER (PARTITION BY cja.UserId) as avg_user_score,
        LAG(cja.post_score) OVER (PARTITION BY cja.UserId ORDER BY cja.post_score) as prev_user_score,
        COALESCE(
            CASE 
                WHEN cja.post_tags IS NOT NULL AND cja.post_tags != '' THEN 
                    string_to_array(cja.post_tags, '><')[1]
                ELSE 'None'
            END, 
            'Default'
        ) as first_tag,
        CASE 
            WHEN LENGTH(cja.post_title) > 100 THEN 
                LEFT(cja.post_title, 100) || '...'
            ELSE cja.post_title
        END as truncated_title,
        CASE 
            WHEN cja.post_answer_count > 0 THEN 
                (cja.post_answer_count * 100.0 / NULLIF(cja.post_comment_count + cja.post_answer_count, 0))
            ELSE 0
        END as answer_ratio,
        CASE 
            WHEN cja.post_count > 50 THEN 'Pro'
            WHEN cja.post_count > 20 THEN 'Advanced'
            WHEN cja.post_count > 5 THEN 'Intermediate'
            ELSE 'Beginner'
        END as experience_level,
        CASE 
            WHEN cja.badge_count > 20 THEN 'Award Winning'
            WHEN cja.badge_count > 10 THEN 'Awarded'
            WHEN cja.badge_count > 0 THEN 'Recognized'
            ELSE 'Novice'
        END as recognition_level,
        CASE 
            WHEN cja.Reputation > 10000 THEN 'Master'
            WHEN cja.Reputation > 5000 THEN 'Expert'
            WHEN cja.Reputation > 1000 THEN 'Advanced'
            ELSE 'Standard'
        END as rep_level,
        CASE 
            WHEN cja.total_score > 10000 THEN 'Legendary Contributor'
            WHEN cja.total_score > 5000 THEN 'Highly Active'
            WHEN cja.total_score > 1000 THEN 'Active'
            ELSE 'Regular'
        END as contribution_level
    FROM CrossJoinAnalysis cja
    WHERE cja.UserId IN (SELECT UserId FROM UserActivityStats WHERE post_count > 10)
),
TagPerformance AS (
    SELECT 
        ta.TagName,
        ta.Count,
        ta.popularity_level,
        ta.popularity_rank,
        ta.growth_rate_percent,
        CASE 
            WHEN ta.growth_rate_percent > 50 THEN 'Rapid Growth'
            WHEN ta.growth_rate_percent > 10 THEN 'Moderate Growth'
            WHEN ta.growth_rate_percent > 0 THEN 'Stable'
            WHEN ta.growth_rate_percent < -50 THEN 'Declining Rapidly'
            WHEN ta.growth_rate_percent < -10 THEN 'Declining'
            ELSE 'Stagnant'
        END as trend_category,
        AVG(ta.Count) OVER (ORDER BY ta.popularity_rank ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as moving_avg_count,
        (ta.Count - AVG(ta.Count) OVER (ORDER BY ta.popularity_rank ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING)) / NULLIF(AVG(ta.Count) OVER (ORDER BY ta.popularity_rank ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING), 0) * 100 as deviation_percent,
        PERCENT_RANK() OVER (ORDER BY ta.Count) as popularity_percentile
    FROM TagAnalysis ta
    WHERE ta.TagName IS NOT NULL AND ta.Count > 0
),
AggregatedResults AS (
    SELECT 
        fa.post_id,
        fa.UserId,
        fa.DisplayName,
        fa.Reputation,
        fa.contribution_level,
        fa.contributor_level,
        fa.experience_level,
        fa.recognition_level,
        fa.rep_level,
        fa.metric_rank,
        fa.metric_percentile,
        fa.combined_metric,
        fa.avg_user_score,
        fa.cumulative_score,
        fa.answer_ratio,
        fa.trend_status,
        fa.post_category,
        fa.activity_status,
        fa.tag_density_level,
        fa.truncated_title,
        fa.first_tag,
        ta.TagName,
        ta.Count as tag_count,
        ta.popularity_level,
        ta.trend_category,
        ta.deviation_percent,
        ROW_NUMBER() OVER (ORDER BY fa.combined_metric DESC) as overall_rank,
        DENSE_RANK() OVER (PARTITION BY fa.contribution_level ORDER BY fa.combined_metric DESC) as level_rank,
        AVG(fa.combined_metric) OVER (PARTITION BY fa.contributor_level) as avg_metric_by_level,
        COUNT(*) OVER (PARTITION BY fa.contributor_level) as contributor_count_by_level,
        CASE 
            WHEN fa.combined_metric > 500 THEN 'High Impact'
            WHEN fa.combined_metric > 100 THEN 'Medium Impact'
            WHEN fa.combined_metric > 10 THEN 'Low Impact'
            ELSE 'Minimal Impact'
        END as impact_level
    FROM FinalAnalysis fa
    FULL OUTER JOIN TagPerformance ta ON 
        (fa.first_tag = ta.TagName OR 
        (fa.post_tags IS NOT NULL AND 
         CONTAINS(fa.post_tags, ta.TagName)))
    WHERE fa.UserId IS NOT NULL
)
SELECT 
    ar.post_id,
    ar.UserId,
    ar.DisplayName,
    ar.Reputation,
    ar.contribution_level,
    ar.contributor_level,
    ar.experience_level,
    ar.recognition_level,
    ar.rep_level,
    ar.metric_rank,
    ar.metric_percentile,
    ar.combined_metric,
    ar.avg_user_score,
    ar.cumulative_score,
    ar.answer_ratio,
    ar.trend_status,
    ar.post_category,
    ar.activity_status,
    ar.tag_density_level,
    ar.truncated_title,
    ar.first_tag,
    ar.TagName,
    ar.tag_count,
    ar.popularity_level,
    ar.trend_category,
    ar.deviation_percent,
    ar.overall_rank,
    ar.level_rank,
    ar.avg_metric_by_level,
    ar.contributor_count_by_level,
    ar.impact_level,
    CASE 
        WHEN ar.metric_rank <= 10 THEN 'Top 10'
        WHEN ar.metric_rank <= 50 THEN 'Top 50'
        WHEN ar.metric_rank <= 100 THEN 'Top 100'
        ELSE 'Below Top 100'
    END as rank_bucket,
    CASE 
        WHEN ar.combined_metric >= 1000 THEN 1
        WHEN ar.combined_metric >= 500 THEN 2
        WHEN ar.combined_metric >= 100 THEN 3
        ELSE 4
    END as metric_band,
    CASE 
        WHEN ar.overall_rank <= 10 THEN TRUE
        WHEN ar.overall_rank <= 50 THEN TRUE  
        ELSE FALSE
    END as is_top_performer,
    CASE 
        WHEN (ar.metric_rank <= 10 AND ar.contributor_level = 'Elite Contributor') THEN 'Elite'
        WHEN (ar.metric_rank <= 50 AND ar.contributor_level = 'Experienced Contributor') THEN 'Highly Active'
        WHEN ar.metric_rank <= 100 THEN 'Active'
        ELSE 'Regular'
    END as performance_status,
    ROUND(ar.combined_metric, 2) as formatted_metric,
    ROUND(ar.avg_metric_by_level, 2) as avg_metric_formatted,
    ROUND(ar.deviation_percent, 2) as deviation_percent_formatted
FROM AggregatedResults ar
WHERE ar.UserId IS NOT NULL
AND (ar.contributor_level LIKE '%Contributor%' OR ar.contribution_level LIKE '%Active%')
AND ar.combined_metric IS NOT NULL
AND ar.combined_metric > 0
ORDER BY ar.combined_metric DESC, ar.overall_rank ASC
LIMIT 5000
OFFSET 0;