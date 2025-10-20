-- {"query": "47007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 16058, "output_tokens": 13811} 

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) as question_count,
        ARRAY[t.TagName] as tag_path,
        1 as depth
    FROM Tags t
    INNER JOIN Posts pt ON pt.Tags LIKE '%<' || t.TagName || '>%'
    WHERE pt.PostTypeId = 1
        AND t.Count > 1000
    GROUP BY t.Id, t.TagName
    
    UNION ALL
    
    SELECT 
        t2.Id,
        t2.TagName,
        COUNT(DISTINCT p2.Id),
        th.tag_path || t2.TagName,
        th.depth + 1
    FROM tag_hierarchy th
    CROSS JOIN Tags t2
    INNER JOIN Posts p1 ON p1.Tags LIKE '%<' || th.TagName || '>%'
    INNER JOIN Posts p2 ON p2.Tags LIKE '%<' || t2.TagName || '>%'
        AND p1.Id = p2.Id
        AND p1.PostTypeId = 1
    WHERE th.depth < 3
        AND t2.TagName != ALL(th.tag_path)
        AND t2.Count > 500
    GROUP BY t2.Id, t2.TagName, th.tag_path, th.depth
),
user_expertise AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        t.TagName,
        COUNT(DISTINCT p.Id) as answers_count,
        SUM(p.Score) as total_score,
        AVG(p.Score) as avg_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score,
        COUNT(DISTINCT CASE WHEN p.Id = q.AcceptedAnswerId THEN p.Id END) as accepted_answers,
        STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Class, b.Date DESC) FILTER (WHERE b.TagBased = B'1') as tag_badges,
        DENSE_RANK() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) as tag_rank
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
    INNER JOIN Posts q ON q.Id = p.ParentId
    INNER JOIN Tags t ON q.Tags LIKE '%<' || t.TagName || '>%'
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Name LIKE '%' || t.TagName || '%'
    WHERE u.Reputation > 5000
        AND p.Score > 0
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
temporal_patterns AS (
    SELECT 
        DATE_TRUNC('quarter', p.CreationDate) as quarter,
        pt.Name as post_type,
        COUNT(*) as post_count,
        AVG(p.Score) as avg_score,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY p.ViewCount) as p95_views,
        COUNT(DISTINCT p.OwnerUserId) as unique_authors,
        COUNT(*) FILTER (WHERE p.ClosedDate IS NOT NULL) as closed_posts,
        AVG(EXTRACT(EPOCH FROM (COALESCE(p.ClosedDate, p.LastActivityDate) - p.CreationDate))/3600.0) as avg_lifetime_hours,
        SUM(COUNT(*)) OVER (PARTITION BY pt.Name ORDER BY DATE_TRUNC('quarter', p.CreationDate)) as cumulative_posts
    FROM Posts p
    INNER JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate >= '2020-01-01'
    GROUP BY DATE_TRUNC('quarter', p.CreationDate), pt.Name
),
edit_patterns AS (
    SELECT 
        ph.PostId,
        p.Title,
        COUNT(DISTINCT ph.UserId) as unique_editors,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) as edit_count,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (7,8,9)) as rollback_count,
        MAX(ph.CreationDate) - MIN(ph.CreationDate) as edit_timespan,
        ARRAY_AGG(DISTINCT pht.Name ORDER BY ph.CreationDate) as history_sequence
    FROM PostHistory ph
    INNER JOIN Posts p ON ph.PostId = p.Id
    INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE p.PostTypeId = 1
        AND p.Score > 50
    GROUP BY ph.PostId, p.Title
    HAVING COUNT(DISTINCT ph.UserId) > 3
)
SELECT 
    th.tag_path[1] as primary_tag,
    COALESCE(th.tag_path[2], '') as secondary_tag,
    COALESCE(th.tag_path[3], '') as tertiary_tag,
    th.question_count,
    ue.DisplayName as top_contributor,
    ue.total_score as contributor_score,
    ue.accepted_answers,
    ue.tag_badges,
    tp.quarter,
    tp.avg_score as quarterly_avg_score,
    tp.p95_views,
    tp.unique_authors,
    ROUND(tp.closed_posts::numeric / NULLIF(tp.post_count, 0) * 100, 2) as close_rate_pct,
    tp.avg_lifetime_hours,
    ep.Title as highly_edited_question,
    ep.unique_editors,
    ep.edit_count,
    ep.rollback_count,
    EXTRACT(EPOCH FROM ep.edit_timespan)/86400.0 as edit_timespan_days,
    CASE 
        WHEN ue.tag_rank = 1 THEN 'Gold Standard Expert'
        WHEN ue.tag_rank <= 5 THEN 'Top Tier Expert'
        WHEN ue.tag_rank <= 20 THEN 'Senior Contributor'
        ELSE 'Active Contributor'
    END as expertise_level,
    LAG(tp.post_count, 4) OVER (PARTITION BY tp.post_type ORDER BY tp.quarter) as year_ago_post_count,
    ROUND(
        (tp.post_count - LAG(tp.post_count, 4) OVER (PARTITION BY tp.post_type ORDER BY tp.quarter))::numeric / 
        NULLIF(LAG(tp.post_count, 4) OVER (PARTITION BY tp.post_type ORDER BY tp.quarter), 0) * 100, 
        2
    ) as yoy_growth_pct
FROM tag_hierarchy th
CROSS JOIN temporal_patterns tp
LEFT JOIN user_expertise ue ON ue.TagName = th.TagName AND ue.tag_rank = 1
LEFT JOIN edit_patterns ep ON ep.edit_count = (SELECT MAX(edit_count) FROM edit_patterns)
WHERE th.depth <= 2
    AND tp.post_type = 'Question'
ORDER BY 
    th.question_count DESC,
    tp.quarter DESC,
    ue.total_score DESC
LIMIT 100;
