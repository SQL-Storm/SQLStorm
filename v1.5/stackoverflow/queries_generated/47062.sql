-- {"query": "47062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 2219}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        CAST(t.TagName AS varchar(1000)) AS tag_path,
        1 AS level
    FROM Tags t
    WHERE t.Count > 10000
    
    UNION ALL
    
    SELECT 
        t2.Id,
        t2.TagName,
        t2.Count,
        CAST(th.tag_path || ' -> ' || t2.TagName AS varchar(1000)),
        th.level + 1
    FROM Tags t2
    JOIN tag_hierarchy th ON t2.Count < th.Count / 2
    WHERE th.level < 3 AND t2.Count > 1000
),
user_expertise AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        STRING_AGG(DISTINCT substring(p.Tags, 2, length(p.Tags)-2), ', ') AS expertise_tags,
        COUNT(DISTINCT p.Id) AS total_posts,
        SUM(p.Score) AS total_score,
        AVG(p.Score)::numeric(10,2) AS avg_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS median_score,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS questions_asked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answers_given,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score >= 10 THEN p.Id END) AS high_quality_answers,
        COUNT(DISTINCT DATE_TRUNC('month', p.CreationDate)) AS active_months
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND p.Score > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) >= 10
),
temporal_patterns AS (
    SELECT 
        DATE_TRUNC('quarter', p.CreationDate) AS quarter,
        pt.Name AS post_type,
        COUNT(*) AS post_count,
        AVG(p.Score) AS avg_score,
        STDDEV(p.Score) AS score_stddev,
        COUNT(DISTINCT p.OwnerUserId) AS unique_contributors,
        SUM(p.ViewCount) AS total_views,
        AVG(p.AnswerCount) FILTER (WHERE p.PostTypeId = 1) AS avg_answers_per_question,
        COUNT(*) FILTER (WHERE p.AcceptedAnswerId IS NOT NULL) AS accepted_answers,
        PERCENTILE_CONT(ARRAY[0.25, 0.5, 0.75, 0.95]) WITHIN GROUP (ORDER BY p.Score) AS score_percentiles,
        LAG(COUNT(*), 1) OVER (PARTITION BY pt.Name ORDER BY DATE_TRUNC('quarter', p.CreationDate)) AS prev_quarter_count,
        LAG(COUNT(*), 4) OVER (PARTITION BY pt.Name ORDER BY DATE_TRUNC('quarter', p.CreationDate)) AS year_ago_count
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate >= '2015-01-01'
    GROUP BY DATE_TRUNC('quarter', p.CreationDate), pt.Name
),
badge_achievements AS (
    SELECT 
        b.UserId,
        b.Name AS badge_name,
        b.Class,
        b.Date AS badge_date,
        DENSE_RANK() OVER (PARTITION BY b.UserId ORDER BY b.Date) AS badge_sequence,
        EXTRACT(DAY FROM b.Date - LAG(b.Date) OVER (PARTITION BY b.UserId ORDER BY b.Date)) AS days_since_last_badge,
        COUNT(*) OVER (PARTITION BY b.UserId, b.Class ORDER BY b.Date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_class_badges,
        FIRST_VALUE(b.Name) OVER (PARTITION BY b.UserId, b.Class ORDER BY b.Date) AS first_badge_in_class
    FROM Badges b
    WHERE b.TagBased = false
),
interaction_network AS (
    SELECT 
        p1.OwnerUserId AS questioner_id,
        p2.OwnerUserId AS answerer_id,
        COUNT(DISTINCT p1.Id) AS questions_answered,
        AVG(p2.Score) AS avg_answer_score,
        SUM(CASE WHEN p2.Id = p1.AcceptedAnswerId THEN 1 ELSE 0 END) AS accepted_answers,
        MIN(p2.CreationDate) AS first_interaction,
        MAX(p2.CreationDate) AS last_interaction,
        STRING_AGG(DISTINCT substring(p1.Tags, 2, length(p1.Tags)-2), ', ' ORDER BY substring(p1.Tags, 2, length(p1.Tags)-2)) AS common_tags
    FROM Posts p1
    JOIN Posts p2 ON p1.Id = p2.ParentId
    WHERE p1.PostTypeId = 1 
        AND p2.PostTypeId = 2
        AND p1.OwnerUserId IS NOT NULL
        AND p2.OwnerUserId IS NOT NULL
        AND p1.OwnerUserId != p2.OwnerUserId
    GROUP BY p1.OwnerUserId, p2.OwnerUserId
    HAVING COUNT(DISTINCT p1.Id) >= 3
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    ue.total_posts,
    ue.total_score,
    ue.avg_score,
    ue.median_score,
    ue.high_quality_answers,
    ue.active_months,
    COALESCE(ue.expertise_tags, 'N/A') AS main_expertise_areas,
    tp.quarter,
    tp.post_type,
    tp.post_count AS quarterly_posts,
    tp.avg_score AS quarterly_avg_score,
    tp.score_percentiles[3] AS q75_score,
    tp.score_percentiles[4] AS q95_score,
    ROUND((tp.post_count::numeric / NULLIF(tp.prev_quarter_count, 0) - 1) * 100, 2) AS qoq_growth_pct,
    ROUND((tp.post_count::numeric / NULLIF(tp.year_ago_count, 0) - 1) * 100, 2) AS yoy_growth_pct,
    ba.badge_name,
    ba.Class AS badge_class,
    ba.badge_sequence,
    ba.days_since_last_badge,
    ba.cumulative_class_badges,
    inn.answerer_id AS top_collaborator_id,
    inn.questions_answered AS collaboration_count,
    inn.avg_answer_score AS collab_avg_score,
    inn.accepted_answers AS collab_accepted,
    EXTRACT(DAY FROM inn.last_interaction - inn.first_interaction) AS collaboration_duration_days,
    th.tag_path AS related_tag_hierarchy,
    th.level AS tag_hierarchy_level,
    DENSE_RANK() OVER (PARTITION BY tp.quarter ORDER BY ue.total_score DESC) AS quarterly_user_rank,
    PERCENT_RANK() OVER (PARTITION BY tp.post_type ORDER BY ue.avg_score DESC) AS percentile_by_post_type,
    ROW_NUMBER() OVER (PARTITION BY ue.UserId ORDER BY ba.badge_date DESC) AS recent_badge_rank
FROM user_expertise ue
CROSS JOIN temporal_patterns tp
LEFT JOIN badge_achievements ba ON ue.UserId = ba.UserId
LEFT JOIN interaction_network inn ON ue.UserId = inn.questioner_id
LEFT JOIN tag_hierarchy th ON ue.expertise_tags LIKE '%' || th.TagName || '%'
WHERE tp.quarter >= '2020-01-01'
    AND tp.post_count > 100
    AND ue.Reputation > 1000
    AND (ba.badge_sequence <= 10 OR ba.badge_sequence IS NULL)
    AND (inn.questions_answered >= 5 OR inn.questions_answered IS NULL)
ORDER BY 
    ue.Reputation DESC,
    tp.quarter DESC,
    tp.post_count DESC,
    ba.badge_date DESC
LIMIT 10000;
