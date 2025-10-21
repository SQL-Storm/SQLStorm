-- {"query": "47023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 52762, "output_tokens": 46241} 

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) as direct_questions,
        1 as level
    FROM Tags t
    JOIN Posts pt ON pt.Tags LIKE '%<' || t.TagName || '>%'
    WHERE pt.PostTypeId = 1
        AND t.Count > 1000
    GROUP BY t.Id, t.TagName
),
user_expertise AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        t.TagName,
        SUM(p.Score) as tag_score,
        COUNT(DISTINCT p.Id) as answer_count,
        AVG(p.Score) as avg_score,
        RANK() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) as tag_rank,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY p.Score) OVER (PARTITION BY t.TagName) as p95_score
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    JOIN Posts q ON q.Id = p.ParentId
    JOIN Tags t ON q.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 2
        AND p.Score > 0
        AND u.Reputation > 5000
    GROUP BY u.Id, u.DisplayName, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
temporal_patterns AS (
    SELECT 
        DATE_TRUNC('month', p.CreationDate) as month,
        pt.Name as post_type,
        COUNT(*) as post_count,
        AVG(p.Score) as avg_score,
        STDDEV(p.Score) as score_stddev,
        SUM(p.ViewCount) as total_views,
        COUNT(DISTINCT p.OwnerUserId) as unique_authors,
        LAG(COUNT(*), 1) OVER (PARTITION BY pt.Name ORDER BY DATE_TRUNC('month', p.CreationDate)) as prev_month_count,
        LAG(COUNT(*), 12) OVER (PARTITION BY pt.Name ORDER BY DATE_TRUNC('month', p.CreationDate)) as year_ago_count
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate >= NOW() - INTERVAL '3 years'
    GROUP BY DATE_TRUNC('month', p.CreationDate), pt.Name
),
badge_progression AS (
    SELECT 
        u.Id,
        u.DisplayName,
        b.Name as badge_name,
        b.Class,
        b.Date,
        ROW_NUMBER() OVER (PARTITION BY u.Id, b.Class ORDER BY b.Date) as badge_sequence,
        LEAD(b.Date) OVER (PARTITION BY u.Id, b.Class ORDER BY b.Date) - b.Date as time_to_next,
        COUNT(*) OVER (PARTITION BY u.Id, b.Class ORDER BY b.Date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as cumulative_badges
    FROM Users u
    JOIN Badges b ON b.UserId = u.Id
    WHERE b.TagBased = 0
),
edit_patterns AS (
    SELECT 
        ph.PostId,
        p.OwnerUserId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) as edit_count,
        COUNT(DISTINCT ph.UserId) as unique_editors,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (7,8,9) THEN 1 END) as rollback_count,
        MAX(ph.CreationDate) - MIN(ph.CreationDate) as edit_timespan,
        STRING_AGG(DISTINCT pht.Name, ', ' ORDER BY pht.Name) as history_types
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE p.PostTypeId IN (1,2)
    GROUP BY ph.PostId, p.OwnerUserId
    HAVING COUNT(*) > 3
)
SELECT 
    ue.DisplayName,
    ue.TagName,
    ue.tag_score,
    ue.answer_count,
    ue.avg_score,
    ue.tag_rank,
    bp.cumulative_badges as gold_badges,
    COALESCE(ep.avg_edit_count, 0) as avg_edits_per_post,
    tp.growth_rate,
    th.total_tag_questions,
    DENSE_RANK() OVER (ORDER BY ue.tag_score * LOG(ue.answer_count + 1) * POWER(ue.avg_score, 0.5) DESC) as overall_expertise_rank,
    CASE 
        WHEN ue.tag_rank = 1 THEN 'Domain Expert'
        WHEN ue.tag_rank <= 5 THEN 'Top Contributor'
        WHEN ue.tag_rank <= 20 THEN 'Active Contributor'
        ELSE 'Regular Contributor'
    END as contributor_tier,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ue.tag_score) OVER (PARTITION BY ue.TagName) as median_tag_score,
    ue.tag_score / NULLIF(ue.p95_score, 0) as relative_performance
FROM user_expertise ue
LEFT JOIN (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) as cumulative_badges
    FROM badge_progression
    WHERE Class = 1
    GROUP BY UserId
) bp ON bp.UserId = ue.UserId
LEFT JOIN (
    SELECT 
        OwnerUserId,
        AVG(edit_count) as avg_edit_count
    FROM edit_patterns
    GROUP BY OwnerUserId
) ep ON ep.OwnerUserId = ue.UserId
LEFT JOIN (
    SELECT 
        post_type,
        AVG((post_count - COALESCE(prev_month_count, post_count)) / NULLIF(prev_month_count, 0)) as growth_rate
    FROM temporal_patterns
    WHERE post_type = 'Question'
    GROUP BY post_type
) tp ON 1=1
LEFT JOIN (
    SELECT 
        TagName,
        SUM(direct_questions) as total_tag_questions
    FROM tag_hierarchy
    GROUP BY TagName
) th ON th.TagName = ue.TagName
WHERE ue.tag_rank <= 10
ORDER BY overall_expertise_rank
LIMIT 100;
