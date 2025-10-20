-- {"query": "47061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 139934, "output_tokens": 123991} 

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) as direct_questions,
        0 as depth
    FROM Tags t
    INNER JOIN Posts pt ON pt.Tags LIKE '%<' || t.TagName || '>%' AND pt.PostTypeId = 1
    WHERE t.Count > 1000
    GROUP BY t.Id, t.TagName
    
    UNION ALL
    
    SELECT 
        t.Id,
        t.TagName,
        th.direct_questions,
        th.depth + 1
    FROM tag_hierarchy th
    CROSS JOIN Tags t
    WHERE th.depth < 3 AND t.Count > 500
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
        SUM(CASE WHEN p.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) as accepted_answers,
        AVG(EXTRACT(EPOCH FROM (COALESCE(p.ClosedDate, CURRENT_TIMESTAMP) - p.CreationDate))/86400) as avg_question_lifetime_days,
        DENSE_RANK() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) as tag_rank
    FROM Users u
    INNER JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    INNER JOIN Posts p ON p.Id = a.ParentId AND p.PostTypeId = 1
    INNER JOIN Tags t ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE u.Reputation > 5000
        AND a.Score > 0
        AND p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
badge_patterns AS (
    SELECT 
        b.UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        COUNT(*) OVER (PARTITION BY b.UserId, b.Name) as badge_count,
        LAG(b.Date) OVER (PARTITION BY b.UserId ORDER BY b.Date) as prev_badge_date,
        EXTRACT(EPOCH FROM (b.Date - LAG(b.Date) OVER (PARTITION BY b.UserId ORDER BY b.Date)))/86400 as days_between_badges,
        FIRST_VALUE(b.Date) OVER (PARTITION BY b.UserId, b.Class ORDER BY b.Date) as first_class_badge_date,
        ROW_NUMBER() OVER (PARTITION BY b.UserId, b.Class ORDER BY b.Date) as class_badge_sequence
    FROM Badges b
    INNER JOIN Users u ON u.Id = b.UserId
    WHERE b.TagBased = false
        AND u.CreationDate < CURRENT_TIMESTAMP - INTERVAL '1 year'
),
post_evolution AS (
    SELECT 
        ph.PostId,
        p.PostTypeId,
        p.Score as current_score,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.Id END) as edit_count,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (7,8,9) THEN ph.Id END) as rollback_count,
        COUNT(DISTINCT ph.UserId) as unique_editors,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) as was_closed,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) as was_reopened,
        STRING_AGG(DISTINCT pht.Name, ', ' ORDER BY pht.Name) as history_types,
        EXTRACT(EPOCH FROM (MAX(ph.CreationDate) - MIN(ph.CreationDate)))/3600 as evolution_hours
    FROM PostHistory ph
    INNER JOIN Posts p ON p.Id = ph.PostId
    INNER JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
    WHERE p.Score >= 10
    GROUP BY ph.PostId, p.PostTypeId, p.Score
),
interaction_network AS (
    SELECT 
        c.UserId as commenter_id,
        p.OwnerUserId as post_owner_id,
        COUNT(DISTINCT c.Id) as comment_interactions,
        AVG(c.Score) as avg_comment_score,
        COUNT(DISTINCT p.Id) as unique_posts_commented,
        SUM(CASE WHEN c.Score > 5 THEN 1 ELSE 0 END) as high_score_comments,
        STDDEV(c.Score) as comment_score_variance
    FROM Comments c
    INNER JOIN Posts p ON p.Id = c.PostId
    WHERE c.UserId IS NOT NULL 
        AND p.OwnerUserId IS NOT NULL
        AND c.UserId != p.OwnerUserId
    GROUP BY c.UserId, p.OwnerUserId
    HAVING COUNT(DISTINCT c.Id) >= 5
)
SELECT 
    ue.DisplayName,
    ue.TagName,
    ue.answers_count,
    ue.total_score,
    ue.avg_score,
    ue.median_score,
    ue.accepted_answers,
    ROUND(ue.accepted_answers::numeric / NULLIF(ue.answers_count, 0) * 100, 2) as acceptance_rate,
    ue.avg_question_lifetime_days,
    ue.tag_rank,
    bp.BadgeName,
    bp.Class as badge_class,
    bp.badge_count,
    bp.days_between_badges,
    bp.class_badge_sequence,
    pe.edit_count,
    pe.rollback_count,
    pe.unique_editors,
    pe.was_closed,
    pe.was_reopened,
    pe.history_types,
    pe.evolution_hours,
    COALESCE(inet.comment_interactions, 0) as total_comment_interactions,
    COALESCE(inet.avg_comment_score, 0) as avg_interaction_comment_score,
    COALESCE(inet.unique_posts_commented, 0) as unique_posts_with_interactions,
    COALESCE(inet.high_score_comments, 0) as high_value_comments,
    ROUND(COALESCE(inet.comment_score_variance, 0), 2) as comment_score_variance,
    th.direct_questions as tag_question_volume,
    ROUND(ue.total_score::numeric / NULLIF(th.direct_questions, 0) * 100, 4) as user_tag_impact_ratio
FROM user_expertise ue
LEFT JOIN badge_patterns bp ON bp.UserId = ue.UserId AND bp.class_badge_sequence <= 3
LEFT JOIN Posts p ON p.OwnerUserId = ue.UserId AND p.PostTypeId = 2
LEFT JOIN post_evolution pe ON pe.PostId = p.ParentId
LEFT JOIN interaction_network inet ON inet.commenter_id = ue.UserId
LEFT JOIN tag_hierarchy th ON th.TagName = ue.TagName AND th.depth = 0
WHERE ue.tag_rank <= 10
    AND ue.avg_score > 5
ORDER BY ue.TagName, ue.tag_rank, ue.total_score DESC
LIMIT 1000;
