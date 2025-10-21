-- {"query": "47060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 2193}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) as direct_questions,
        t.TagName as root_tag,
        0 as level
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
        th.root_tag,
        th.level + 1
    FROM tag_hierarchy th
    INNER JOIN Tags t2 ON t2.Id != th.Id
    INNER JOIN Posts p1 ON p1.Tags LIKE '%<' || th.TagName || '>%'
    INNER JOIN Posts p2 ON p2.Tags LIKE '%<' || t2.TagName || '>%'
        AND p1.Id = p2.Id
        AND p1.PostTypeId = 1
    WHERE th.level < 3
    GROUP BY t2.Id, t2.TagName, th.root_tag, th.level
),
user_expertise AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        t.TagName,
        SUM(p.Score) as tag_score,
        COUNT(DISTINCT p.Id) as answer_count,
        AVG(p.Score) as avg_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId = a.Id THEN a.Id END) as accepted_answers,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) as tag_rank,
        DENSE_RANK() OVER (ORDER BY SUM(p.Score) DESC) as overall_rank
    FROM Users u
    INNER JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    INNER JOIN Posts p ON p.Id = a.ParentId AND p.PostTypeId = 1
    INNER JOIN Tags t ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE u.Reputation > 5000
        AND a.Score > 0
        AND a.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
temporal_patterns AS (
    SELECT 
        EXTRACT(DOW FROM p.CreationDate) as day_of_week,
        EXTRACT(HOUR FROM p.CreationDate) as hour_of_day,
        pt.Name as post_type,
        COUNT(*) as post_count,
        AVG(p.Score) as avg_score,
        AVG(p.ViewCount) as avg_views,
        AVG(p.AnswerCount) as avg_answers,
        STDDEV(p.Score) as score_stddev,
        MAX(p.Score) - MIN(p.Score) as score_range,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY p.Score) as p95_score
    FROM Posts p
    INNER JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
        AND p.Score IS NOT NULL
    GROUP BY EXTRACT(DOW FROM p.CreationDate), EXTRACT(HOUR FROM p.CreationDate), pt.Name
),
edit_patterns AS (
    SELECT 
        ph.PostId,
        COUNT(DISTINCT ph.UserId) as unique_editors,
        COUNT(*) as total_edits,
        MAX(ph.CreationDate) - MIN(ph.CreationDate) as edit_timespan,
        STRING_AGG(DISTINCT pht.Name, ', ' ORDER BY pht.Name) as edit_types,
        AVG(LENGTH(ph.Text)) as avg_edit_size,
        BOOL_OR(ph.UserId != p.OwnerUserId) as has_community_edits
    FROM PostHistory ph
    INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    INNER JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (2,5,8)
        AND p.Score > 10
    GROUP BY ph.PostId
),
badge_correlations AS (
    SELECT 
        b1.Name as badge1,
        b2.Name as badge2,
        COUNT(DISTINCT b1.UserId) as users_with_both,
        COUNT(DISTINCT b1.UserId)::FLOAT / NULLIF(COUNT(DISTINCT u.Id), 0) as correlation_strength,
        AVG(u.Reputation) as avg_reputation,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY u.Reputation) as median_reputation
    FROM Badges b1
    INNER JOIN Badges b2 ON b1.UserId = b2.UserId 
        AND b1.Name < b2.Name
        AND b1.Class = b2.Class
    INNER JOIN Users u ON b1.UserId = u.Id
    WHERE b1.TagBased = 0 
        AND b2.TagBased = 0
    GROUP BY b1.Name, b2.Name
    HAVING COUNT(DISTINCT b1.UserId) >= 100
)
SELECT 
    th.root_tag,
    th.TagName as related_tag,
    th.direct_questions,
    ue.DisplayName as top_expert,
    ue.tag_score as expert_score,
    ue.accepted_answers,
    tp.day_of_week,
    tp.hour_of_day,
    tp.avg_score as hourly_avg_score,
    tp.p95_score,
    ep.unique_editors,
    ep.total_edits,
    ep.edit_types,
    bc.badge1,
    bc.badge2,
    bc.correlation_strength,
    COALESCE(v.upvotes, 0) as recent_upvotes,
    COALESCE(v.downvotes, 0) as recent_downvotes,
    COALESCE(v.bounty_total, 0) as bounty_amount,
    ROW_NUMBER() OVER (PARTITION BY th.root_tag ORDER BY ue.tag_score DESC, tp.p95_score DESC) as rank_in_category,
    CASE 
        WHEN ue.tag_rank = 1 THEN 'Gold Expert'
        WHEN ue.tag_rank <= 10 THEN 'Silver Expert'
        WHEN ue.tag_rank <= 50 THEN 'Bronze Expert'
        ELSE 'Contributor'
    END as expertise_level,
    GREATEST(
        0,
        LOG(2, NULLIF(th.direct_questions, 0)) * 
        LOG(10, NULLIF(ue.tag_score, 0)) * 
        COALESCE(tp.p95_score, 1)
    )::NUMERIC(10,2) as composite_impact_score
FROM tag_hierarchy th
LEFT JOIN user_expertise ue ON ue.TagName = th.TagName AND ue.tag_rank = 1
LEFT JOIN temporal_patterns tp ON tp.post_type = 'Question'
LEFT JOIN edit_patterns ep ON ep.unique_editors > 5
LEFT JOIN badge_correlations bc ON bc.users_with_both > 500
LEFT JOIN LATERAL (
    SELECT 
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) as upvotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) as downvotes,
        SUM(CASE WHEN VoteTypeId = 8 THEN BountyAmount ELSE 0 END) as bounty_total
    FROM Votes v
    INNER JOIN Posts p ON v.PostId = p.Id
    WHERE p.Tags LIKE '%<' || th.TagName || '>%'
        AND v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
) v ON true
WHERE th.level <= 2
    AND th.direct_questions > 100
ORDER BY composite_impact_score DESC, th.root_tag, th.level, th.direct_questions DESC
LIMIT 1000;
