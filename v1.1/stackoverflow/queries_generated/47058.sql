-- {"query": "47058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 133052, "output_tokens": 117810} 

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) as direct_questions,
        t.TagName as tag_path,
        1 as level
    FROM Tags t
    JOIN Posts pt ON pt.Tags LIKE '%<' || t.TagName || '>%'
    WHERE pt.PostTypeId = 1
        AND t.Count > 1000
    GROUP BY t.Id, t.TagName
    
    UNION ALL
    
    SELECT 
        t2.Id,
        t2.TagName,
        th.direct_questions,
        th.tag_path || ' -> ' || t2.TagName,
        th.level + 1
    FROM tag_hierarchy th
    JOIN Posts p1 ON p1.Tags LIKE '%<' || SPLIT_PART(th.tag_path, ' -> ', -1) || '>%'
    JOIN Posts p2 ON p2.Id = p1.Id AND p2.Tags LIKE '%<' || t2.TagName || '>%'
    JOIN Tags t2 ON t2.TagName != ALL(STRING_TO_ARRAY(th.tag_path, ' -> '))
    WHERE th.level < 3
        AND p1.PostTypeId = 1
        AND t2.Count > 500
),
expert_answerers AS (
    SELECT 
        u.Id as user_id,
        u.DisplayName,
        t.TagName,
        COUNT(DISTINCT a.Id) as answers,
        AVG(a.Score) as avg_score,
        SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) as accepted_answers,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) as median_score,
        STDDEV(a.Score) as score_stddev,
        MAX(a.Score) as max_answer_score,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY COUNT(DISTINCT a.Id) DESC) as rank_in_tag
    FROM Users u
    JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
    JOIN Tags t ON q.Tags LIKE '%<' || t.TagName || '>%'
    WHERE u.Reputation > 10000
        AND a.Score > 0
        AND a.CreationDate > NOW() - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, t.TagName
    HAVING COUNT(DISTINCT a.Id) >= 10
),
temporal_activity AS (
    SELECT 
        DATE_TRUNC('month', p.CreationDate) as month,
        pt.Name as post_type,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT p.OwnerUserId) as unique_users,
        AVG(p.Score) as avg_score,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY p.ViewCount) as p95_views,
        SUM(p.ViewCount) as total_views,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.Id END) as edit_count,
        LAG(COUNT(DISTINCT p.Id), 1) OVER (PARTITION BY pt.Name ORDER BY DATE_TRUNC('month', p.CreationDate)) as prev_month_posts,
        LAG(COUNT(DISTINCT p.Id), 12) OVER (PARTITION BY pt.Name ORDER BY DATE_TRUNC('month', p.CreationDate)) as year_ago_posts
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE p.CreationDate > NOW() - INTERVAL '3 years'
    GROUP BY DATE_TRUNC('month', p.CreationDate), pt.Name
),
badge_correlation AS (
    SELECT 
        b1.Name as badge1,
        b2.Name as badge2,
        COUNT(DISTINCT b1.UserId) as users_with_both,
        COUNT(DISTINCT b1.UserId)::FLOAT / NULLIF(COUNT(DISTINCT u.Id), 0) as correlation_coefficient,
        AVG(u.Reputation) as avg_reputation,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY u.Reputation) as median_reputation
    FROM Badges b1
    JOIN Badges b2 ON b1.UserId = b2.UserId AND b1.Name < b2.Name
    JOIN Users u ON u.Id = b1.UserId
    WHERE b1.Class = 1 
        AND b2.Class = 1
        AND b1.Date > NOW() - INTERVAL '1 year'
        AND b2.Date > NOW() - INTERVAL '1 year'
    GROUP BY b1.Name, b2.Name
    HAVING COUNT(DISTINCT b1.UserId) > 50
)
SELECT 
    th.tag_path,
    th.level as tag_depth,
    th.direct_questions,
    ea.DisplayName as top_expert,
    ea.answers as expert_answer_count,
    ea.avg_score as expert_avg_score,
    ea.accepted_answers,
    ea.median_score as expert_median_score,
    ta.month,
    ta.post_count as monthly_posts,
    ta.unique_users as monthly_active_users,
    ta.avg_score as monthly_avg_score,
    ta.p95_views,
    CASE 
        WHEN ta.prev_month_posts IS NOT NULL 
        THEN ((ta.post_count - ta.prev_month_posts)::FLOAT / NULLIF(ta.prev_month_posts, 0)) * 100 
        ELSE 0 
    END as month_over_month_growth,
    CASE 
        WHEN ta.year_ago_posts IS NOT NULL 
        THEN ((ta.post_count - ta.year_ago_posts)::FLOAT / NULLIF(ta.year_ago_posts, 0)) * 100 
        ELSE 0 
    END as year_over_year_growth,
    bc.badge1,
    bc.badge2,
    bc.users_with_both as badge_pair_users,
    bc.correlation_coefficient as badge_correlation,
    bc.avg_reputation as badge_pair_avg_reputation,
    DENSE_RANK() OVER (ORDER BY th.direct_questions DESC, ea.avg_score DESC) as overall_rank,
    COUNT(*) OVER (PARTITION BY th.level) as tags_at_level,
    SUM(ta.post_count) OVER (PARTITION BY ta.month ORDER BY th.direct_questions DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as cumulative_posts_by_month
FROM tag_hierarchy th
LEFT JOIN expert_answerers ea ON ea.TagName = SPLIT_PART(th.tag_path, ' -> ', 1) AND ea.rank_in_tag = 1
LEFT JOIN temporal_activity ta ON ta.post_type = 'Question'
LEFT JOIN badge_correlation bc ON bc.users_with_both > 100
WHERE th.direct_questions > 100
ORDER BY th.direct_questions DESC, ta.month DESC, bc.correlation_coefficient DESC
LIMIT 10000;
