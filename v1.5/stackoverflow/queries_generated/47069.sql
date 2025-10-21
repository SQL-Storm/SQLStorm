-- {"query": "47069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 158286, "output_tokens": 140569} 

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT p.Id) as question_count,
        AVG(p.Score) as avg_score
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
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
        AVG(p.Score) as avg_answer_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score,
        COUNT(DISTINCT CASE WHEN p.Score >= 10 THEN p.Id END) as great_answers,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId = p.Id THEN p.Id END) as accepted_answers
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id
    INNER JOIN Posts q ON q.Id = p.ParentId
    INNER JOIN Tags t ON q.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 2 
        AND u.Reputation > 1000
        AND p.Score > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 5
),
question_lifecycle AS (
    SELECT 
        q.Id as QuestionId,
        q.CreationDate as question_created,
        MIN(a.CreationDate) as first_answer_time,
        MAX(a.CreationDate) as last_answer_time,
        EXTRACT(EPOCH FROM (MIN(a.CreationDate) - q.CreationDate))/3600 as hours_to_first_answer,
        COUNT(DISTINCT a.Id) as total_answers,
        COUNT(DISTINCT CASE WHEN a.Score > 0 THEN a.Id END) as positive_answers,
        MAX(a.Score) as best_answer_score,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as upvotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as downvotes,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) as edit_count,
        q.ViewCount,
        q.Score as question_score,
        CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END as has_accepted
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Comments c ON c.PostId = q.Id
    LEFT JOIN Votes v ON v.PostId = q.Id
    LEFT JOIN PostHistory ph ON ph.PostId = q.Id
    WHERE q.PostTypeId = 1 
        AND q.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND q.Score >= 5
    GROUP BY q.Id, q.CreationDate, q.ViewCount, q.Score, q.AcceptedAnswerId
),
badge_correlation AS (
    SELECT 
        b1.Name as badge1,
        b2.Name as badge2,
        COUNT(DISTINCT b1.UserId) as users_with_both,
        COUNT(DISTINCT b1.UserId)::FLOAT / NULLIF((
            SELECT COUNT(DISTINCT UserId) 
            FROM Badges 
            WHERE Name = b1.Name
        ), 0) as correlation_strength
    FROM Badges b1
    INNER JOIN Badges b2 ON b1.UserId = b2.UserId 
        AND b1.Name < b2.Name
        AND b1.Class = 1 
        AND b2.Class = 1
    GROUP BY b1.Name, b2.Name
    HAVING COUNT(DISTINCT b1.UserId) >= 10
),
monthly_trends AS (
    SELECT 
        DATE_TRUNC('month', p.CreationDate) as month,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) as questions,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) as answers,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) as avg_question_score,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) as avg_answer_score,
        COUNT(DISTINCT p.OwnerUserId) as active_users,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY u.Reputation) as p90_reputation
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '5 years'
    GROUP BY DATE_TRUNC('month', p.CreationDate)
)
SELECT 
    ue.DisplayName,
    ue.TagName,
    ue.Reputation,
    ue.answers_in_tag,
    ue.avg_answer_score,
    ue.median_score,
    ue.great_answers,
    ue.accepted_answers,
    ROUND(ue.accepted_answers::NUMERIC / NULLIF(ue.answers_in_tag, 0) * 100, 2) as acceptance_rate,
    th.question_count as tag_total_questions,
    th.avg_score as tag_avg_score,
    ql.hours_to_first_answer,
    ql.total_answers,
    ql.positive_answers,
    ql.best_answer_score,
    ql.ViewCount,
    ql.question_score,
    bc.badge2 as correlated_badge,
    bc.correlation_strength,
    mt.month,
    mt.questions as monthly_questions,
    mt.avg_question_score as monthly_avg_score,
    mt.p90_reputation as monthly_p90_rep,
    ROW_NUMBER() OVER (PARTITION BY ue.TagName ORDER BY ue.total_score_in_tag DESC) as rank_in_tag,
    DENSE_RANK() OVER (ORDER BY ue.Reputation DESC) as overall_rep_rank,
    LAG(ue.avg_answer_score, 1) OVER (PARTITION BY ue.UserId ORDER BY ue.TagName) as prev_tag_avg_score,
    LEAD(ue.avg_answer_score, 1) OVER (PARTITION BY ue.UserId ORDER BY ue.TagName) as next_tag_avg_score
FROM user_expertise ue
LEFT JOIN tag_hierarchy th ON th.TagName = ue.TagName
LEFT JOIN question_lifecycle ql ON ql.question_score > 10
LEFT JOIN badge_correlation bc ON bc.users_with_both > 50
LEFT JOIN monthly_trends mt ON mt.month >= CURRENT_DATE - INTERVAL '1 year'
WHERE ue.avg_answer_score > 5
    AND th.question_count > 100
ORDER BY ue.total_score_in_tag DESC, ue.Reputation DESC
LIMIT 1000;
