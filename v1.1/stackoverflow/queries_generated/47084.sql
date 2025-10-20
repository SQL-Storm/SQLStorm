-- {"query": "47084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 192696, "output_tokens": 169515} 

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT p.Id) as question_count,
        AVG(p.Score) as avg_score,
        1 as level
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 1
        AND t.Count > 1000
    GROUP BY t.Id, t.TagName
    
    UNION ALL
    
    SELECT 
        t2.Id,
        t2.TagName,
        COUNT(DISTINCT p2.Id),
        AVG(p2.Score),
        th.level + 1
    FROM tag_hierarchy th
    JOIN Posts p1 ON p1.Tags LIKE '%<' || th.TagName || '>%'
    JOIN Posts p2 ON p2.Tags LIKE '%<' || th.TagName || '>%'
        AND p2.Id != p1.Id
        AND p2.Tags != p1.Tags
    JOIN Tags t2 ON p2.Tags LIKE '%<' || t2.TagName || '>%'
        AND t2.Id != th.Id
    WHERE th.level < 3
        AND p1.PostTypeId = 1
        AND p2.PostTypeId = 1
    GROUP BY t2.Id, t2.TagName, th.level
),
user_expertise AS (
    SELECT 
        u.Id as user_id,
        u.DisplayName,
        t.TagName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as answer_score,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Id = q.AcceptedAnswerId THEN p.Id END) as accepted_answers,
        COUNT(DISTINCT b.Id) as tag_badges,
        DENSE_RANK() OVER (PARTITION BY t.TagName ORDER BY SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) DESC) as expertise_rank
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    JOIN Tags t ON p.Tags LIKE '%<' || t.TagName || '>%'
    LEFT JOIN Posts q ON q.AcceptedAnswerId = p.Id
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Name = t.TagName AND b.TagBased = true
    WHERE u.Reputation > 10000
        AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, t.TagName
),
temporal_patterns AS (
    SELECT 
        DATE_TRUNC('month', p.CreationDate) as month,
        t.TagName,
        COUNT(DISTINCT p.Id) as posts,
        COUNT(DISTINCT p.OwnerUserId) as unique_users,
        AVG(p.Score) as avg_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY p.Score) as p95_score,
        COUNT(DISTINCT CASE WHEN p.ClosedDate IS NOT NULL THEN p.Id END) as closed_posts,
        AVG(CASE WHEN p.AnswerCount > 0 THEN p.AnswerCount END) as avg_answers,
        LAG(COUNT(DISTINCT p.Id), 1) OVER (PARTITION BY t.TagName ORDER BY DATE_TRUNC('month', p.CreationDate)) as prev_month_posts,
        LAG(COUNT(DISTINCT p.Id), 12) OVER (PARTITION BY t.TagName ORDER BY DATE_TRUNC('month', p.CreationDate)) as year_ago_posts
    FROM Posts p
    JOIN Tags t ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '5 years'
    GROUP BY DATE_TRUNC('month', p.CreationDate), t.TagName
),
edit_patterns AS (
    SELECT 
        ph.PostId,
        p.OwnerUserId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) as edit_count,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN ph.Id END) as rollback_count,
        COUNT(DISTINCT ph.UserId) as unique_editors,
        MAX(CASE WHEN ph.UserId != p.OwnerUserId THEN 1 ELSE 0 END) as has_community_edits,
        STRING_AGG(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END, ',') as close_reasons
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE p.Score > 10
    GROUP BY ph.PostId, p.OwnerUserId
)
SELECT 
    th.TagName as primary_tag,
    th.level as tag_level,
    th.question_count,
    ROUND(th.avg_score::numeric, 2) as tag_avg_score,
    ue.DisplayName as top_expert,
    ue.answers as expert_answers,
    ue.answer_score as expert_total_score,
    ue.accepted_answers as expert_accepted,
    tp.month,
    tp.posts as monthly_posts,
    tp.unique_users as monthly_active_users,
    ROUND(tp.avg_score::numeric, 2) as monthly_avg_score,
    ROUND(tp.median_score::numeric, 2) as monthly_median_score,
    ROUND(100.0 * tp.closed_posts / NULLIF(tp.posts, 0), 2) as close_rate_pct,
    ROUND(100.0 * (tp.posts - COALESCE(tp.prev_month_posts, 0)) / NULLIF(tp.prev_month_posts, 0), 2) as month_over_month_growth,
    ROUND(100.0 * (tp.posts - COALESCE(tp.year_ago_posts, 0)) / NULLIF(tp.year_ago_posts, 0), 2) as year_over_year_growth,
    ep.edit_count,
    ep.rollback_count,
    ep.unique_editors,
    CASE WHEN ep.has_community_edits = 1 THEN 'Yes' ELSE 'No' END as has_community_edits,
    ep.close_reasons
FROM tag_hierarchy th
JOIN user_expertise ue ON ue.TagName = th.TagName AND ue.expertise_rank = 1
JOIN temporal_patterns tp ON tp.TagName = th.TagName
LEFT JOIN Posts p ON p.Tags LIKE '%<' || th.TagName || '>%' 
    AND p.PostTypeId = 1 
    AND DATE_TRUNC('month', p.CreationDate) = tp.month
LEFT JOIN edit_patterns ep ON ep.PostId = p.Id
WHERE th.level <= 2
    AND tp.posts > 100
    AND tp.month >= CURRENT_TIMESTAMP - INTERVAL '1 year'
ORDER BY 
    th.question_count DESC,
    tp.month DESC,
    th.level,
    tp.year_over_year_growth DESC NULLS LAST
LIMIT 1000;
