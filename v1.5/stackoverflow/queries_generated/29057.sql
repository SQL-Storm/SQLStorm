-- {"query": "29057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2007} 
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
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_views,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as score_category,
        COALESCE(p.Tags, '') as clean_tags,
        COALESCE(p.Title, 'No Title') as clean_title
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
    AND p.CreationDate >= '2020-01-01'
),
UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as total_posts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as question_count,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as answer_count,
        AVG(p.Score) as avg_score,
        MAX(p.CreationDate) as last_activity,
        STRING_AGG(DISTINCT COALESCE(p.Tags, ''), ', ') as all_tags_used,
        COUNT(DISTINCT v.Id) as total_votes,
        COUNT(DISTINCT c.Id) as total_comments,
        COUNT(DISTINCT b.Id) as total_badges,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Elite'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Veteran'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Active'
            ELSE 'New'
        END as user_status
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2015-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Obscure'
        END as tag_popularity,
        STRING_AGG(p.Title, ' | ') as sample_titles,
        COUNT(p.Id) as related_posts,
        AVG(p.Score) as avg_related_score
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE t.TagName IS NOT NULL
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
),
ComplexPostAnalysis AS (
    SELECT 
        rp.Id as PostId,
        rp.Title,
        rp.Tags,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.OwnerUserId,
        rp.prev_score,
        rp.prev_views,
        rp.score_category,
        rp.clean_tags,
        rp.clean_title,
        CASE 
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Avg'
            WHEN rp.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Below Avg'
            ELSE 'Avg'
        END as score_comparison,
        COALESCE(rp.AnswerCount, 0) as answer_count,
        COALESCE(rp.CommentCount, 0) as comment_count,
        COALESCE(rp.FavoriteCount, 0) as favorite_count,
        CASE 
            WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN rp.ParentId IS NOT NULL THEN 'Answer'
            ELSE 'Question'
        END as post_status,
        DATEDIFF(day, rp.CreationDate, CURRENT_TIMESTAMP) as days_since_creation,
        CASE 
            WHEN rp.ViewCount > 1000 THEN 'High Traffic'
            WHEN rp.ViewCount > 100 THEN 'Medium Traffic'
            WHEN rp.ViewCount > 10 THEN 'Low Traffic'
            ELSE 'Minimal Traffic'
        END as traffic_level,
        (rp.Score + COALESCE(rp.ViewCount, 0) + COALESCE(rp.AnswerCount, 0)) as combined_metric,
        (COALESCE(rp.Score, 0) * COALESCE(rp.ViewCount, 0)) as score_view_product,
        (COALESCE(rp.AnswerCount, 0) * COALESCE(rp.CommentCount, 0)) as answer_comment_product
    FROM RankedPosts rp
    WHERE rp.rn <= 3
)
SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.total_posts,
    uas.question_count,
    uas.answer_count,
    uas.avg_score,
    uas.total_votes,
    uas.total_comments,
    uas.total_badges,
    uas.user_status,
    ta.TagName,
    ta.tag_popularity,
    ta.Count as tag_count,
    ta.sample_titles,
    ta.related_posts,
    ta.avg_related_score,
    cpa.PostId,
    cpa.Title,
    cpa.Tags,
    cpa.Score,
    cpa.ViewCount,
    cpa.days_since_creation,
    cpa.score_comparison,
    cpa.answer_count,
    cpa.comment_count,
    cpa.favorite_count,
    cpa.post_status,
    cpa.traffic_level,
    cpa.combined_metric,
    cpa.score_view_product,
    cpa.answer_comment_product,
    CASE 
        WHEN cpa.combined_metric > (SELECT AVG(combined_metric) FROM ComplexPostAnalysis) THEN 'Above Average Post'
        WHEN cpa.combined_metric < (SELECT AVG(combined_metric) FROM ComplexPostAnalysis) THEN 'Below Average Post'
        ELSE 'Average Post'
    END as post_performance_rating,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = uas.UserId AND p2.CreationDate >= '2022-01-01') as recent_posts_count,
    (SELECT STRING_AGG(ta2.TagName, ', ') FROM Tags ta2 
     INNER JOIN Posts p3 ON p3.Tags LIKE '%' || ta2.TagName || '%' 
     WHERE p3.OwnerUserId = uas.UserId AND p3.PostTypeId = 1 
     GROUP BY p3.OwnerUserId HAVING COUNT(*) > 0) as user_tag_specialization,
    CASE 
        WHEN uas.total_votes > uas.total_posts * 2 THEN 'Highly Engaged'
        WHEN uas.total_votes > uas.total_posts THEN 'Engaged'
        ELSE 'Moderately Engaged'
    END as engagement_level,
    (SELECT AVG(cp2.combined_metric) FROM ComplexPostAnalysis cp2 
     INNER JOIN Posts p4 ON p4.Id = cp2.PostId 
     WHERE p4.OwnerUserId = uas.UserId AND cp2.days_since_creation <= 30) as recent_avg_metric,
    (SELECT STRING_AGG(COALESCE(b2.Name, 'Unknown'), ', ') 
     FROM Badges b2 
     WHERE b2.UserId = uas.UserId 
     AND b2.Date >= '2022-01-01'
     GROUP BY b2.UserId) as recent_badges,
    (SELECT COUNT(*) FROM Posts p5 
     WHERE p5.OwnerUserId = uas.UserId 
     AND p5.PostTypeId = 1 
     AND p5.Score > 50) as high_scoring_questions,
    (SELECT COUNT(*) FROM Posts p6 
     WHERE p6.OwnerUserId = uas.UserId 
     AND p6.PostTypeId = 2 
     AND p6.Score > 25) as high_scoring_answers
FROM UserActivityStats uas
LEFT JOIN ComplexPostAnalysis cpa ON uas.UserId = cpa.OwnerUserId
LEFT JOIN TagAnalysis ta ON ta.TagName IN (
    SELECT unnest(string_to_array(COALESCE(cpa.Tags, ''), '><')) 
    WHERE unnest(string_to_array(COALESCE(cpa.Tags, ''), '><')) IS NOT NULL
)
WHERE uas.total_posts > 5
AND uas.last_activity >= '2022-01-01'
AND (
    (cpa.PostId IS NOT NULL AND cpa.score_comparison IN ('Above Avg', 'High')) OR
    (ta.TagName IS NOT NULL AND ta.tag_popularity IN ('Popular', 'Moderate'))
)
ORDER BY uas.Reputation DESC, uas.total_posts DESC, cpa.combined_metric DESC
LIMIT 1000;