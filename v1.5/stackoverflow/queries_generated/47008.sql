-- {"query": "47008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1739}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) as question_count,
        1 as level
    FROM Tags t
    INNER JOIN Posts pt ON pt.Tags LIKE '%<' || t.TagName || '>%'
    WHERE pt.PostTypeId = 1
        AND t.Count > 1000
    GROUP BY t.Id, t.TagName
),
expert_users AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        t.TagName,
        COUNT(DISTINCT p.Id) as answers,
        SUM(p.Score) as total_score,
        AVG(p.Score) as avg_score,
        COUNT(DISTINCT CASE WHEN p.Id = q.AcceptedAnswerId THEN p.Id END) as accepted_answers,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
    INNER JOIN Posts q ON q.Id = p.ParentId
    INNER JOIN tag_hierarchy t ON q.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.Score > 0
        AND u.Reputation > 10000
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
badge_patterns AS (
    SELECT 
        b.UserId,
        STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Name) as gold_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as gold_count,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as silver_count,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as bronze_count,
        EXTRACT(EPOCH FROM (MAX(b.Date) - MIN(b.Date)))/86400 as badge_span_days
    FROM Badges b
    WHERE b.Class = 1
    GROUP BY b.UserId
),
post_evolution AS (
    SELECT 
        ph.PostId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.Id END) as edit_count,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (7,8,9) THEN ph.Id END) as rollback_count,
        COUNT(DISTINCT ph.UserId) as unique_editors,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) as close_reason,
        BOOL_OR(ph.PostHistoryTypeId = 16) as became_community_wiki,
        EXTRACT(EPOCH FROM (MAX(ph.CreationDate) - MIN(ph.CreationDate)))/3600 as evolution_hours
    FROM PostHistory ph
    GROUP BY ph.PostId
),
comment_analysis AS (
    SELECT 
        c.PostId,
        COUNT(*) as comment_count,
        AVG(LENGTH(c.Text)) as avg_comment_length,
        COUNT(DISTINCT c.UserId) as unique_commenters,
        MAX(c.Score) as max_comment_score,
        STRING_AGG(CASE WHEN c.Score >= 5 THEN SUBSTRING(c.Text, 1, 50) END, ' | ' ORDER BY c.Score DESC) as top_comments
    FROM Comments c
    GROUP BY c.PostId
)
SELECT 
    th.TagName,
    eu.DisplayName as expert_name,
    eu.answers,
    eu.total_score,
    eu.avg_score,
    eu.accepted_answers,
    eu.median_score,
    ROUND(100.0 * eu.accepted_answers / eu.answers, 2) as acceptance_rate,
    bp.gold_count,
    bp.silver_count,
    bp.bronze_count,
    bp.gold_badges,
    COALESCE(bp.badge_span_days, 0) as badge_collection_days,
    COUNT(DISTINCT p.Id) as recent_questions,
    SUM(p.ViewCount) as total_views,
    AVG(pe.edit_count) as avg_edits_per_post,
    AVG(pe.evolution_hours) as avg_evolution_time,
    AVG(ca.comment_count) as avg_comments,
    AVG(ca.avg_comment_length) as avg_comment_size,
    COUNT(DISTINCT pl.RelatedPostId) as linked_posts,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) as duplicate_targets,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as upvotes_received,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) as downvotes_received,
    ROUND(AVG(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate))/86400), 2) as avg_activity_span_days,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY p.Score) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY p.Score) as score_iqr
FROM expert_users eu
INNER JOIN tag_hierarchy th ON th.TagName = eu.TagName
LEFT JOIN badge_patterns bp ON bp.UserId = eu.UserId
INNER JOIN Posts p ON p.OwnerUserId = eu.UserId AND p.PostTypeId = 1
LEFT JOIN post_evolution pe ON pe.PostId = p.Id
LEFT JOIN comment_analysis ca ON ca.PostId = p.Id
LEFT JOIN PostLinks pl ON pl.PostId = p.Id
LEFT JOIN Votes v ON v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = eu.UserId)
WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    AND p.Score >= 5
GROUP BY 
    th.TagName,
    eu.DisplayName,
    eu.answers,
    eu.total_score,
    eu.avg_score,
    eu.accepted_answers,
    eu.median_score,
    bp.gold_count,
    bp.silver_count,
    bp.bronze_count,
    bp.gold_badges,
    bp.badge_span_days
HAVING COUNT(DISTINCT p.Id) >= 5
ORDER BY 
    eu.total_score DESC,
    acceptance_rate DESC,
    bp.gold_count DESC
LIMIT 100;
