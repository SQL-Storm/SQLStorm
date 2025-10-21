-- {"query": "47056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1947}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) as direct_questions,
        t.WikiPostId
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    JOIN Posts pt ON pt.Id = p.Id AND pt.PostTypeId = 1
    WHERE t.Count > 1000
    GROUP BY t.Id, t.TagName, t.WikiPostId
),
user_expertise AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        t.TagName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as answer_score,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as question_score,
        COUNT(DISTINCT b.Id) as tag_badges,
        MAX(b.Class) as best_badge_class
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    JOIN tag_hierarchy t ON p.Tags LIKE '%<' || t.TagName || '>%'
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Name = t.TagName AND b.TagBased = B'1'
    WHERE u.Reputation > 5000
    GROUP BY u.Id, u.DisplayName, t.TagName
    HAVING COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 10
),
temporal_patterns AS (
    SELECT 
        DATE_TRUNC('month', p.CreationDate) as month,
        COUNT(DISTINCT p.Id) as posts_created,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) as questions_closed,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as questions_accepted,
        AVG(CASE WHEN p.PostTypeId = 2 THEN EXTRACT(EPOCH FROM (p.CreationDate - parent.CreationDate))/3600 END) as avg_answer_time_hours,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) as edit_events,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as upvotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as downvotes
    FROM Posts p
    LEFT JOIN Posts parent ON p.ParentId = parent.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.CreationDate >= NOW() - INTERVAL '2 years'
    GROUP BY DATE_TRUNC('month', p.CreationDate)
),
network_analysis AS (
    SELECT 
        u1.Id as user1_id,
        u2.Id as user2_id,
        COUNT(DISTINCT p1.Id) as interactions,
        SUM(CASE WHEN p2.AcceptedAnswerId = p1.Id THEN 1 ELSE 0 END) as accepted_answers,
        AVG(c.Score) as avg_comment_score,
        COUNT(DISTINCT pl.Id) as linked_posts
    FROM Users u1
    JOIN Posts p1 ON p1.OwnerUserId = u1.Id
    JOIN Posts p2 ON p2.Id = p1.ParentId OR p2.ParentId = p1.Id
    JOIN Users u2 ON u2.Id = p2.OwnerUserId
    LEFT JOIN Comments c ON c.PostId IN (p1.Id, p2.Id) AND c.UserId IN (u1.Id, u2.Id)
    LEFT JOIN PostLinks pl ON (pl.PostId = p1.Id AND pl.RelatedPostId = p2.Id) OR (pl.PostId = p2.Id AND pl.RelatedPostId = p1.Id)
    WHERE u1.Id < u2.Id 
        AND u1.Reputation > 10000 
        AND u2.Reputation > 10000
    GROUP BY u1.Id, u2.Id
    HAVING COUNT(DISTINCT p1.Id) > 5
)
SELECT 
    ue.DisplayName,
    ue.TagName,
    ue.answers,
    ue.answer_score,
    ROUND(ue.answer_score::numeric / NULLIF(ue.answers, 0), 2) as avg_answer_score,
    ue.questions,
    ue.question_score,
    ue.tag_badges,
    ue.best_badge_class,
    th.direct_questions as tag_total_questions,
    ROUND(100.0 * ue.answers / NULLIF(th.direct_questions, 0), 2) as tag_coverage_pct,
    tp.posts_created as recent_month_posts,
    tp.median_score as recent_median_score,
    tp.avg_answer_time_hours,
    COALESCE(na.total_interactions, 0) as network_interactions,
    COALESCE(na.total_accepted, 0) as network_accepted_answers,
    DENSE_RANK() OVER (PARTITION BY ue.TagName ORDER BY ue.answer_score DESC) as tag_rank,
    DENSE_RANK() OVER (ORDER BY ue.answer_score DESC) as global_rank,
    STRING_AGG(DISTINCT other_tags.TagName, ', ' ORDER BY other_tags.TagName) FILTER (
        WHERE other_tags.TagName != ue.TagName 
        AND EXISTS (
            SELECT 1 FROM Posts p3 
            WHERE p3.OwnerUserId = ue.UserId 
            AND p3.Tags LIKE '%<' || other_tags.TagName || '>%'
            AND p3.Score > 10
        )
    ) as other_expertise_tags
FROM user_expertise ue
JOIN tag_hierarchy th ON th.TagName = ue.TagName
CROSS JOIN LATERAL (
    SELECT * FROM temporal_patterns 
    WHERE month = DATE_TRUNC('month', NOW() - INTERVAL '1 month')
    LIMIT 1
) tp
LEFT JOIN LATERAL (
    SELECT 
        SUM(interactions) as total_interactions,
        SUM(accepted_answers) as total_accepted
    FROM network_analysis
    WHERE user1_id = ue.UserId OR user2_id = ue.UserId
) na ON true
LEFT JOIN Tags other_tags ON other_tags.Count > 500
WHERE ue.answer_score > 100
GROUP BY 
    ue.DisplayName, ue.TagName, ue.answers, ue.answer_score,
    ue.questions, ue.question_score, ue.tag_badges, ue.best_badge_class,
    th.direct_questions, tp.posts_created, tp.median_score,
    tp.avg_answer_time_hours, na.total_interactions, na.total_accepted, ue.UserId
ORDER BY ue.answer_score DESC
LIMIT 100;
