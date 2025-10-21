-- {"query": "47095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 217930, "output_tokens": 193382} 
WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT p.Id) as question_count,
        AVG(p.Score) as avg_score
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 1
    GROUP BY t.Id, t.TagName
),
user_expertise AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        t.TagName,
        COUNT(DISTINCT p.Id) as answers_in_tag,
        SUM(p.Score) as total_score_in_tag,
        AVG(p.Score) as avg_score_in_tag,
        COUNT(DISTINCT CASE WHEN p.Id = q.AcceptedAnswerId THEN p.Id END) as accepted_answers,
        RANK() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) as rank_in_tag
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    JOIN Posts q ON p.ParentId = q.Id
    JOIN Tags t ON q.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 2
        AND u.Reputation > 1000
        AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 5
),
question_lifecycle AS (
    SELECT 
        p.Id as QuestionId,
        p.CreationDate as question_created,
        p.Score as question_score,
        p.ViewCount,
        p.AnswerCount,
        MIN(a.CreationDate) as first_answer_time,
        MAX(a.CreationDate) as last_answer_time,
        COUNT(DISTINCT a.OwnerUserId) as unique_answerers,
        AVG(a.Score) as avg_answer_score,
        EXTRACT(EPOCH FROM (MIN(a.CreationDate) - p.CreationDate))/3600 as hours_to_first_answer,
        COUNT(DISTINCT c.UserId) as unique_commenters,
        COUNT(DISTINCT ph.UserId) as unique_editors,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) as edit_count,
        MAX(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) as has_accepted
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '1 year'
        AND p.ViewCount > 100
    GROUP BY p.Id, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount
),
badge_patterns AS (
    SELECT 
        b.Name as badge_name,
        b.Class as badge_class,
        COUNT(DISTINCT b.UserId) as recipients,
        AVG(u.Reputation) as avg_recipient_reputation,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY u.Reputation) as median_reputation,
        COUNT(DISTINCT CASE WHEN DATE_PART('year', b.Date) = DATE_PART('year', cast('2024-10-01' as date)) THEN b.UserId END) as current_year_recipients,
        AVG(EXTRACT(EPOCH FROM (b.Date - u.CreationDate))/86400) as avg_days_to_earn
    FROM Badges b
    JOIN Users u ON b.UserId = u.Id
    WHERE b.TagBased = false
    GROUP BY b.Name, b.Class
    HAVING COUNT(DISTINCT b.UserId) >= 10
),
voting_patterns AS (
    SELECT 
        DATE_TRUNC('week', v.CreationDate) as vote_week,
        vt.Name as vote_type,
        COUNT(*) as vote_count,
        COUNT(DISTINCT v.UserId) as unique_voters,
        COUNT(DISTINCT v.PostId) as unique_posts_voted,
        AVG(p.Score) as avg_post_score,
        STDDEV(p.Score) as stddev_post_score
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    JOIN Posts p ON v.PostId = p.Id
    WHERE v.CreationDate >= cast('2024-10-01' as date) - INTERVAL '6 months'
        AND v.VoteTypeId IN (2, 3, 8, 9)
    GROUP BY DATE_TRUNC('week', v.CreationDate), vt.Name
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    ue.TagName,
    ue.rank_in_tag,
    ue.answers_in_tag,
    ue.avg_score_in_tag,
    ue.accepted_answers,
    th.question_count as tag_question_count,
    th.avg_score as tag_avg_score,
    ql.question_score,
    ql.ViewCount,
    ql.hours_to_first_answer,
    ql.unique_answerers,
    ql.edit_count,
    bp.badge_name,
    bp.badge_class,
    bp.avg_days_to_earn,
    vp.vote_week,
    vp.vote_type,
    vp.vote_count,
    vp.avg_post_score,
    DENSE_RANK() OVER (ORDER BY ue.Reputation DESC) as global_reputation_rank,
    PERCENT_RANK() OVER (PARTITION BY ue.TagName ORDER BY ue.total_score_in_tag) as percentile_in_tag,
    LAG(vp.vote_count, 1) OVER (PARTITION BY vp.vote_type ORDER BY vp.vote_week) as prev_week_votes,
    LEAD(vp.vote_count, 1) OVER (PARTITION BY vp.vote_type ORDER BY vp.vote_week) as next_week_votes,
    CASE 
        WHEN ql.hours_to_first_answer < 1 THEN 'Very Fast'
        WHEN ql.hours_to_first_answer < 24 THEN 'Fast'
        WHEN ql.hours_to_first_answer < 168 THEN 'Normal'
        ELSE 'Slow'
    END as response_speed_category,
    NTILE(10) OVER (ORDER BY ue.Reputation) as reputation_decile
FROM user_expertise ue
CROSS JOIN LATERAL (
    SELECT * FROM tag_hierarchy th 
    WHERE th.TagName = ue.TagName
    LIMIT 1
) th
CROSS JOIN LATERAL (
    SELECT * FROM question_lifecycle ql 
    WHERE ql.question_score > 0
    ORDER BY ql.ViewCount DESC
    LIMIT 5
) ql
CROSS JOIN LATERAL (
    SELECT * FROM badge_patterns bp 
    WHERE bp.badge_class IN (1, 2)
    ORDER BY bp.avg_days_to_earn
    LIMIT 3
) bp
CROSS JOIN LATERAL (
    SELECT * FROM voting_patterns vp
    WHERE vp.vote_count > 100
    ORDER BY vp.vote_week DESC
    LIMIT 10
) vp
WHERE ue.rank_in_tag <= 10
ORDER BY 
    ue.Reputation DESC,
    ue.TagName,
    ql.ViewCount DESC,
    vp.vote_week DESC
LIMIT 1000;