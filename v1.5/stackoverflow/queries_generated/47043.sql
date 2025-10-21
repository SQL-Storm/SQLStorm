-- {"query": "47043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 2221}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) as direct_questions,
        1 as level
    FROM Tags t
    JOIN Posts pt ON pt.Tags LIKE '%<' || t.TagName || '>%' AND pt.PostTypeId = 1
    WHERE t.Count > 1000
    GROUP BY t.Id, t.TagName
),
expert_users AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        t.TagName,
        COUNT(DISTINCT p.Id) as answers_in_tag,
        SUM(p.Score) as total_score,
        AVG(p.Score) as avg_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId = p.Id THEN p.Id END) as accepted_answers,
        DENSE_RANK() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) as tag_rank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 2
    JOIN Posts q ON p.ParentId = q.Id AND q.PostTypeId = 1
    JOIN Tags t ON q.Tags LIKE '%<' || t.TagName || '>%'
    WHERE u.Reputation > 10000
        AND p.Score > 0
        AND t.Count > 500
    GROUP BY u.Id, u.DisplayName, u.Reputation, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
question_complexity AS (
    SELECT 
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        LENGTH(p.Body) as body_length,
        (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', ''))) / 2 + 1 as tag_count,
        COALESCE(p.ViewCount, 0) / NULLIF(p.AnswerCount, 0) as views_per_answer,
        EXTRACT(EPOCH FROM (COALESCE(a.CreationDate, CURRENT_TIMESTAMP) - p.CreationDate))/3600 as hours_to_first_answer,
        COUNT(DISTINCT ph.Id) as edit_count,
        COUNT(DISTINCT c.Id) as comment_count,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) as was_closed,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) as was_reopened
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
        AND a.CreationDate = (SELECT MIN(CreationDate) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2)
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
        AND p.Score >= 5
    GROUP BY p.Id, p.Title, p.Tags, p.Score, p.ViewCount, p.AnswerCount, p.Body, a.CreationDate, p.CreationDate
),
badge_patterns AS (
    SELECT 
        b.Name as badge_name,
        b.Class,
        COUNT(DISTINCT b.UserId) as total_recipients,
        COUNT(DISTINCT CASE WHEN eu.UserId IS NOT NULL THEN b.UserId END) as expert_recipients,
        AVG(u.Reputation) as avg_recipient_reputation,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY u.Reputation) as q1_reputation,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY u.Reputation) as q3_reputation,
        STRING_AGG(DISTINCT eu.TagName, ', ' ORDER BY eu.TagName) FILTER (WHERE eu.tag_rank = 1) as top_expert_tags
    FROM Badges b
    JOIN Users u ON b.UserId = u.Id
    LEFT JOIN expert_users eu ON eu.UserId = b.UserId AND eu.tag_rank <= 3
    WHERE b.TagBased = 0
        AND b.Date >= CURRENT_TIMESTAMP - INTERVAL '1 year'
    GROUP BY b.Name, b.Class
    HAVING COUNT(DISTINCT b.UserId) >= 50
),
temporal_patterns AS (
    SELECT 
        DATE_TRUNC('week', p.CreationDate) as week,
        COUNT(DISTINCT p.Id) as questions,
        COUNT(DISTINCT a.Id) as answers,
        AVG(p.Score) as avg_question_score,
        AVG(a.Score) as avg_answer_score,
        COUNT(DISTINCT p.OwnerUserId) as unique_askers,
        COUNT(DISTINCT a.OwnerUserId) as unique_answerers,
        SUM(v.BountyAmount) as total_bounty,
        LAG(COUNT(DISTINCT p.Id), 1) OVER (ORDER BY DATE_TRUNC('week', p.CreationDate)) as prev_week_questions,
        LAG(COUNT(DISTINCT p.Id), 52) OVER (ORDER BY DATE_TRUNC('week', p.CreationDate)) as year_ago_questions
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 8
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '3 years'
    GROUP BY DATE_TRUNC('week', p.CreationDate)
)
SELECT 
    th.TagName,
    th.direct_questions,
    COALESCE(eu.expert_count, 0) as num_experts,
    COALESCE(eu.top_expert, 'N/A') as top_expert,
    COALESCE(eu.top_expert_score, 0) as top_expert_total_score,
    ROUND(AVG(qc.body_length), 0) as avg_question_length,
    ROUND(AVG(qc.tag_count), 1) as avg_tags_per_question,
    ROUND(AVG(qc.views_per_answer), 1) as avg_views_per_answer,
    ROUND(AVG(qc.hours_to_first_answer), 1) as avg_hours_to_first_answer,
    ROUND(AVG(qc.edit_count), 2) as avg_edits_per_question,
    ROUND(AVG(qc.was_closed) * 100, 1) as close_rate,
    COUNT(DISTINCT bp.badge_name) as related_badges,
    ROUND(AVG(tp.growth_rate), 1) as avg_weekly_growth_rate,
    CORR(qc.body_length, qc.Score)::NUMERIC(5,3) as length_score_correlation,
    CORR(qc.tag_count, qc.AnswerCount)::NUMERIC(5,3) as tags_answers_correlation
FROM tag_hierarchy th
LEFT JOIN LATERAL (
    SELECT 
        COUNT(*) as expert_count,
        MAX(DisplayName) FILTER (WHERE tag_rank = 1) as top_expert,
        MAX(total_score) FILTER (WHERE tag_rank = 1) as top_expert_score
    FROM expert_users
    WHERE TagName = th.TagName
) eu ON true
LEFT JOIN question_complexity qc ON qc.Tags LIKE '%<' || th.TagName || '>%'
LEFT JOIN badge_patterns bp ON bp.top_expert_tags LIKE '%' || th.TagName || '%'
LEFT JOIN LATERAL (
    SELECT AVG((questions - prev_week_questions) * 100.0 / NULLIF(prev_week_questions, 0)) as growth_rate
    FROM temporal_patterns
    WHERE week >= CURRENT_TIMESTAMP - INTERVAL '6 months'
) tp ON true
GROUP BY 
    th.TagName, 
    th.direct_questions, 
    eu.expert_count, 
    eu.top_expert, 
    eu.top_expert_score
HAVING COUNT(DISTINCT qc.Id) >= 100
ORDER BY th.direct_questions DESC
LIMIT 50;
