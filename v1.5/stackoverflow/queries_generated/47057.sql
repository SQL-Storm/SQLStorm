-- {"query": "47057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 2320}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT p.Id) as question_count,
        1 as level
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 1
        AND t.Count > 1000
    GROUP BY t.Id, t.TagName
),
user_expertise AS (
    SELECT 
        u.Id as user_id,
        u.DisplayName,
        u.Reputation,
        t.TagName,
        COUNT(DISTINCT p.Id) as answers_in_tag,
        SUM(p.Score) as total_score_in_tag,
        AVG(p.Score) as avg_score_in_tag,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score,
        STDDEV(p.Score) as score_stddev,
        MAX(p.Score) as max_answer_score,
        COUNT(DISTINCT CASE WHEN p.Id = q.AcceptedAnswerId THEN p.Id END) as accepted_answers,
        COUNT(DISTINCT b.Id) as tag_badges,
        DENSE_RANK() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) as tag_rank
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
    INNER JOIN Posts q ON q.Id = p.ParentId AND q.PostTypeId = 1
    INNER JOIN Tags t ON q.Tags LIKE '%<' || t.TagName || '>%'
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.TagBased = 1 AND b.Name = t.TagName
    WHERE u.Reputation > 5000
        AND p.Score > 0
        AND p.CreationDate > CURRENT_DATE - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
temporal_activity AS (
    SELECT 
        DATE_TRUNC('month', p.CreationDate) as activity_month,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions_asked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers_posted,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) as avg_question_score,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) as avg_answer_score,
        COUNT(DISTINCT p.OwnerUserId) as active_users,
        COUNT(DISTINCT c.UserId) as commenting_users,
        SUM(p.ViewCount) as total_views,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY p.Score) as p95_score,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) as edit_count,
        LAG(COUNT(DISTINCT p.Id), 1) OVER (ORDER BY DATE_TRUNC('month', p.CreationDate)) as prev_month_posts,
        LAG(COUNT(DISTINCT p.Id), 12) OVER (ORDER BY DATE_TRUNC('month', p.CreationDate)) as year_ago_posts
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE p.CreationDate > CURRENT_DATE - INTERVAL '3 years'
    GROUP BY DATE_TRUNC('month', p.CreationDate)
),
network_analysis AS (
    SELECT 
        u1.Id as user1_id,
        u1.DisplayName as user1_name,
        u2.Id as user2_id,
        u2.DisplayName as user2_name,
        COUNT(DISTINCT p1.Id) as interaction_count,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as upvotes_exchanged,
        COUNT(DISTINCT pl.Id) as linked_posts,
        AVG(ABS(EXTRACT(EPOCH FROM (p2.CreationDate - p1.CreationDate))/3600)) as avg_response_time_hours,
        CORR(p1.Score, p2.Score) as score_correlation,
        COUNT(DISTINCT t.TagName) as common_tags
    FROM Users u1
    INNER JOIN Posts p1 ON p1.OwnerUserId = u1.Id AND p1.PostTypeId = 1
    INNER JOIN Posts p2 ON p2.ParentId = p1.Id AND p2.PostTypeId = 2
    INNER JOIN Users u2 ON u2.Id = p2.OwnerUserId
    LEFT JOIN Votes v ON v.PostId = p2.Id AND v.UserId = u1.Id
    LEFT JOIN PostLinks pl ON (pl.PostId = p1.Id AND pl.RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u2.Id))
    LEFT JOIN Tags t ON p1.Tags LIKE '%<' || t.TagName || '>%'
    WHERE u1.Id != u2.Id
        AND u1.Reputation > 10000
        AND u2.Reputation > 10000
    GROUP BY u1.Id, u1.DisplayName, u2.Id, u2.DisplayName
    HAVING COUNT(DISTINCT p1.Id) >= 5
)
SELECT 
    ue.user_id,
    ue.DisplayName,
    ue.Reputation,
    ue.TagName,
    ue.answers_in_tag,
    ue.total_score_in_tag,
    ue.avg_score_in_tag,
    ue.median_score,
    ue.score_stddev,
    ue.accepted_answers,
    ROUND(100.0 * ue.accepted_answers / NULLIF(ue.answers_in_tag, 0), 2) as acceptance_rate,
    ue.tag_badges,
    ue.tag_rank,
    th.question_count as tag_total_questions,
    ta.activity_month,
    ta.questions_asked,
    ta.answers_posted,
    ta.avg_question_score,
    ta.avg_answer_score,
    ta.active_users,
    ta.total_views,
    ta.edit_count,
    ROUND(100.0 * (ta.questions_asked - COALESCE(ta.prev_month_posts, 0)) / NULLIF(ta.prev_month_posts, 1), 2) as month_over_month_growth,
    ROUND(100.0 * (ta.questions_asked - COALESCE(ta.year_ago_posts, 0)) / NULLIF(ta.year_ago_posts, 1), 2) as year_over_year_growth,
    na.user2_id as collaborator_id,
    na.user2_name as collaborator_name,
    na.interaction_count,
    na.upvotes_exchanged,
    na.linked_posts,
    na.avg_response_time_hours,
    na.score_correlation,
    na.common_tags,
    ROW_NUMBER() OVER (PARTITION BY ue.TagName ORDER BY ue.total_score_in_tag DESC, ue.accepted_answers DESC) as overall_tag_ranking,
    DENSE_RANK() OVER (ORDER BY ue.Reputation DESC) as global_reputation_rank,
    NTILE(100) OVER (ORDER BY ue.avg_score_in_tag) as score_percentile,
    FIRST_VALUE(ue.DisplayName) OVER (PARTITION BY ue.TagName ORDER BY ue.total_score_in_tag DESC) as tag_top_contributor,
    LAG(ue.total_score_in_tag, 1) OVER (PARTITION BY ue.user_id ORDER BY ue.TagName) as prev_tag_score,
    LEAD(ue.total_score_in_tag, 1) OVER (PARTITION BY ue.user_id ORDER BY ue.TagName) as next_tag_score
FROM user_expertise ue
CROSS JOIN LATERAL (
    SELECT * FROM tag_hierarchy th 
    WHERE th.TagName = ue.TagName 
    LIMIT 1
) th
CROSS JOIN LATERAL (
    SELECT * FROM temporal_activity ta 
    ORDER BY ta.activity_month DESC 
    LIMIT 1
) ta
LEFT JOIN LATERAL (
    SELECT * FROM network_analysis na 
    WHERE na.user1_id = ue.user_id 
    ORDER BY na.interaction_count DESC 
    LIMIT 3
) na ON true
WHERE ue.tag_rank <= 20
ORDER BY ue.TagName, ue.tag_rank, na.interaction_count DESC;
