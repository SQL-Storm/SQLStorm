-- {"query": "7514.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1480} 
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
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as moving_avg_score,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'High'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Low'
            ELSE 'Average'
        END as score_category
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(p.Score), 0) as total_score,
        COUNT(DISTINCT p.Id) as post_count,
        MAX(p.CreationDate) as last_post_date,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT b.Id) as badge_count,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN ' prolific'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN ' active'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN ' engaged'
            ELSE ' casual'
        END as activity_level
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE((SELECT COUNT(*) FROM Posts WHERE Tags LIKE '%' || t.TagName || '%'), 0) as usage_count,
        CASE 
            WHEN t.Count > 1000 THEN 'popular'
            WHEN t.Count > 100 THEN 'moderate'
            WHEN t.Count > 10 THEN ' niche'
            ELSE 'rare'
        END as popularity_level,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) - t.Count as popularity_change
    FROM Tags t
),
PostWithDetails AS (
    SELECT 
        rp.Id,
        rp.Title,
        rp.Tags,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.rn,
        rp.prev_score,
        rp.moving_avg_score,
        rp.score_category,
        ua.DisplayName as owner_name,
        ua.total_score,
        ua.post_count,
        ua.comment_count,
        ua.badge_count,
        ua.activity_level,
        ta.popularity_level,
        ta.usage_count,
        ta.popularity_change,
        CASE 
            WHEN rp.Score > 0 AND rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Average'
            WHEN rp.Score > 0 AND rp.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Below Average'
            ELSE 'Standard'
        END as score_rank,
        CONCAT('Post #', rp.Id, ' by ', ua.DisplayName, ' - Score: ', rp.Score, ' Views: ', rp.ViewCount) as post_summary
    FROM RankedPosts rp
    INNER JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
    LEFT JOIN TagAnalysis ta ON rp.Tags LIKE '%' || ta.TagName || '%'
    WHERE rp.score_category IN ('High', 'Average') 
        AND ua.Reputation > 1000
        AND ua.post_count > 10
),
FinalAnalysis AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY total_score DESC, post_count DESC) as user_ranking,
        DENSE_RANK() OVER (ORDER BY popularity_level, usage_count DESC) as tag_ranking,
        NTILE(5) OVER (ORDER BY Score) as score_tier,
        PERCENT_RANK() OVER (ORDER BY Score) as score_percentile,
        (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1) as total_questions,
        (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2) as total_answers
    FROM PostWithDetails
)
SELECT 
    CONCAT(fa.post_summary, ' (Rank: ', fa.user_ranking, ')') as final_summary,
    fa.Score,
    fa.ViewCount,
    fa.CreationDate,
    fa.owner_name,
    fa.total_score,
    fa.post_count,
    fa.comment_count,
    fa.badge_count,
    fa.activity_level,
    fa.popularity_level,
    fa.usage_count,
    fa.score_rank,
    fa.score_tier,
    fa.score_percentile,
    CASE 
        WHEN fa.total_score > (SELECT AVG(total_score) FROM UserActivity) 
        AND fa.post_count > (SELECT AVG(post_count) FROM UserActivity) 
        THEN 'Top Performer'
        ELSE 'Regular User'
    END as user_performance,
    COALESCE(
        (SELECT DISTINCT TOP 1 p.Title FROM Posts p WHERE p.Id = fa.AcceptedAnswerId),
        'No accepted answer'
    ) as accepted_answer_title,
    CASE 
        WHEN fa.score_change IS NULL THEN 'No previous score'
        ELSE CONCAT('Change: ', CAST(fa.prev_score - fa.Score AS VARCHAR), ' from ', fa.prev_score)
    END as score_change_analysis
FROM FinalAnalysis fa
LEFT JOIN (
    SELECT 
        Id,
        PrevScore,
        Score,
        PrevScore - Score as score_change
    FROM (
        SELECT 
            Id,
            LAG(Score) OVER (ORDER BY CreationDate) as PrevScore,
            Score
        FROM Posts 
        WHERE PostTypeId = 1
    ) t
    WHERE PrevScore IS NOT NULL
) sc ON fa.Id = sc.Id
WHERE 
    fa.score_category IN ('High', 'Average') 
    AND fa.Tags IS NOT NULL
    AND fa.Tags != ''
    AND fa.Tags NOT LIKE '%null%'
    AND (
        fa.popularity_level = 'popular'
        OR fa.score_rank = 'Above Average'
        OR fa.activity_level IN (' prolific', ' active')
    )
    AND (
        fa.total_score > (SELECT AVG(total_score) FROM UserActivity WHERE post_count > 50)
        OR fa.post_count > (SELECT AVG(post_count) FROM UserActivity)
    )
ORDER BY fa.total_score DESC, fa.post_count DESC, fa.CreationDate DESC
LIMIT 1000;