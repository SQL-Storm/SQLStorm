-- {"query": "7078.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2301} 
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
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as user_post_rank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as score_rank,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as prev_score,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as next_score,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as mov_avg_score,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            WHEN p.Score > 0 THEN 'Low'
            ELSE 'Negative'
        END as score_category,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                ARRAY_LENGTH(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1)
            ELSE 0 
        END as tag_count,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 
            0
        ) as comment_count_with_subquery,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2 AND a.DeletionDate IS NULL)
            ELSE 0
        END as answer_count_with_correlated,
        COALESCE(
            (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8), 
            0
        ) as avg_bounty_amount
    FROM Posts p
    WHERE p.CreationDate >= '2018-01-01' 
      AND p.PostTypeId IN (1, 2) 
      AND p.Score IS NOT NULL
),
PostMetrics AS (
    SELECT 
        rp.*,
        CASE 
            WHEN rp.prev_score IS NOT NULL THEN rp.Score - rp.prev_score
            ELSE 0 
        END as score_change_from_prev,
        CASE 
            WHEN rp.next_score IS NOT NULL THEN rp.next_score - rp.Score
            ELSE 0 
        END as score_change_to_next,
        CASE 
            WHEN rp.score_rank <= 100 THEN 'Top100'
            WHEN rp.score_rank <= 1000 THEN 'Top1000'
            ELSE 'Other'
        END as rank_category,
        IIF(rp.tag_count > 5, 'Many Tags', 'Few Tags') as tag_category,
        IIF(rp.AnswerCount > 10, 'High Answer Count', 'Low Answer Count') as answer_category,
        CASE 
            WHEN rp.ViewCount > 10000 THEN 'High Views'
            WHEN rp.ViewCount > 1000 THEN 'Medium Views'
            ELSE 'Low Views'
        END as view_category,
        (rp.Score * rp.AnswerCount) / NULLIF(rp.ViewCount, 0) as score_per_view_ratio
    FROM RankedPosts rp
),
UserMetrics AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount as user_views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answer_count,
        COALESCE(SUM(p.Score), 0) as total_score,
        COALESCE(AVG(p.Score), 0) as avg_score,
        MAX(p.CreationDate) as last_post_date,
        COALESCE(COUNT(DISTINCT b.Id), 0) as total_badges,
        COALESCE(COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END), 0) as gold_badges,
        COALESCE(COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END), 0) as silver_badges,
        COALESCE(COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END), 0) as bronze_badges,
        COALESCE(MAX(b.Date), '1900-01-01'::timestamp) as last_badge_date,
        MAX(CASE WHEN b.Class = 1 THEN b.Date END) as last_gold_badge_date,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN COUNT(DISTINCT p.Id) * 100.0 / NULLIF(COUNT(DISTINCT p.Id) + COUNT(DISTINCT a.Id), 0)
            ELSE 0 
        END as question_percentage,
        ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) as user_score_rank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2) 
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2018-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount, u.UpVotes, u.DownVotes
    HAVING COUNT(DISTINCT p.Id) >= 1 OR COUNT(DISTINCT b.Id) >= 1
),
ComplexCalculations AS (
    SELECT 
        pm.*,
        um.DisplayName as owner_name,
        um.Reputation as owner_reputation,
        um.total_posts,
        um.total_score,
        um.avg_score,
        pm.score_change_from_prev,
        pm.score_change_to_next,
        pm.score_per_view_ratio,
        pm.score_category,
        pm.tag_count,
        pm.tag_category,
        pm.answer_count_with_correlated,
        pm.comment_count_with_subquery,
        pm.avg_bounty_amount,
        CASE 
            WHEN pm.score_per_view_ratio > 1 THEN 'High Engagement'
            WHEN pm.score_per_view_ratio > 0.5 THEN 'Medium Engagement'
            ELSE 'Low Engagement'
        END as engagement_level,
        CASE 
            WHEN pm.user_post_rank = 1 THEN 'Most Recent Post'
            WHEN pm.user_post_rank = 2 THEN 'Second Most Recent Post'
            ELSE 'Other'
        END as user_post_status,
        EXTRACT(DAY FROM (NOW() - pm.CreationDate)) as days_since_creation,
        CASE 
            WHEN pm.Score > 50 AND pm.AnswerCount > 10 THEN 'Popular Question'
            WHEN pm.Score > 100 THEN 'Highly Rated'
            WHEN pm.ViewCount > 1000 THEN 'Highly Viewed'
            ELSE 'Standard Post'
        END as post_category
    FROM PostMetrics pm
    INNER JOIN UserMetrics um ON pm.OwnerUserId = um.UserId
    WHERE pm.Score > 0 
      AND pm.ViewCount > 0 
      AND pm.AnswerCount IS NOT NULL
),
AggregatedPerformance AS (
    SELECT 
        'Question' as post_type,
        COUNT(*) as total_questions,
        AVG(Score) as avg_question_score,
        SUM(ViewCount) as total_views,
        AVG(AnswerCount) as avg_answers,
        AVG(CommentCount) as avg_comments,
        AVG(FavoriteCount) as avg_favorites,
        AVG(tag_count) as avg_tags,
        COUNT(DISTINCT OwnerUserId) as unique_owners
    FROM ComplexCalculations 
    WHERE PostTypeId = 1
    
    UNION ALL
    
    SELECT 
        'Answer' as post_type,
        COUNT(*) as total_answers,
        AVG(Score) as avg_answer_score,
        SUM(ViewCount) as total_views,
        NULL as avg_answers,
        AVG(CommentCount) as avg_comments,
        AVG(FavoriteCount) as avg_favorites,
        NULL as avg_tags,
        COUNT(DISTINCT OwnerUserId) as unique_owners
    FROM ComplexCalculations 
    WHERE PostTypeId = 2
    
    UNION ALL
    
    SELECT 
        'Combined' as post_type,
        COUNT(*) as total_posts,
        AVG(Score) as avg_score,
        SUM(ViewCount) as total_views,
        AVG(AnswerCount) as avg_answers,
        AVG(CommentCount) as avg_comments,
        AVG(FavoriteCount) as avg_favorites,
        AVG(tag_count) as avg_tags,
        COUNT(DISTINCT OwnerUserId) as unique_owners
    FROM ComplexCalculations
)
SELECT 
    ap.post_type,
    ap.total_questions,
    ap.avg_question_score,
    ap.total_views,
    ap.avg_answers,
    ap.avg_comments,
    ap.avg_favorites,
    ap.avg_tags,
    ap.unique_owners,
    (CASE 
        WHEN ap.total_questions > 0 THEN 
            (SELECT COUNT(*) FROM ComplexCalculations cc 
             WHERE cc.post_category = 'Popular Question' 
               AND cc.PostTypeId = 1) * 100.0 / ap.total_questions
        ELSE 0 
    END) as popular_question_percentage,
    (CASE 
        WHEN ap.total_answers > 0 THEN 
            (SELECT COUNT(*) FROM ComplexCalculations cc 
             WHERE cc.post_category = 'Highly Rated' 
               AND cc.PostTypeId = 2) * 100.0 / ap.total_answers
        ELSE 0 
    END) as highly_rated_answer_percentage,
    (SELECT COUNT(*) FROM ComplexCalculations cc 
     WHERE cc.engagement_level = 'High Engagement') as highly_engaged_posts,
    (SELECT COUNT(*) FROM ComplexCalculations cc 
     WHERE cc.answer_category = 'High Answer Count') as high_answer_count_posts,
    (SELECT COUNT(*) FROM ComplexCalculations cc 
     WHERE cc.view_category = 'High Views') as high_view_posts,
    (SELECT MAX(um.user_score_rank) FROM UserMetrics um) as max_user_rank,
    (SELECT AVG(um.avg_score) FROM UserMetrics um) as overall_avg_user_score
FROM AggregatedPerformance ap
GROUP BY 
    ap.post_type,
    ap.total_questions,
    ap.avg_question_score,
    ap.total_views,
    ap.avg_answers,
    ap.avg_comments,
    ap.avg_favorites,
    ap.avg_tags,
    ap.unique_owners
ORDER BY 
    CASE ap.post_type 
        WHEN 'Question' THEN 1 
        WHEN 'Answer' THEN 2 
        WHEN 'Combined' THEN 3 
    END;