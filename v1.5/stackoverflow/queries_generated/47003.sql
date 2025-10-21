-- {"query": "47003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1848}

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
    
    UNION ALL
    
    SELECT 
        t.Id,
        t.TagName,
        th.question_count,
        th.level + 1
    FROM Tags t
    INNER JOIN tag_hierarchy th ON th.Id != t.Id
    WHERE th.level < 3
),
user_expertise AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        string_agg(DISTINCT t.TagName, ', ' ORDER BY t.TagName) as expert_tags,
        COUNT(DISTINCT p.Id) as total_answers,
        AVG(p.Score) as avg_answer_score,
        SUM(CASE WHEN p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) as accepted_answers,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
    INNER JOIN Posts q ON q.Id = p.ParentId
    INNER JOIN Tags t ON q.Tags LIKE '%<' || t.TagName || '>%'
    WHERE u.Reputation > 10000
        AND p.Score > 5
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 50
),
question_lifecycle AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score as question_score,
        p.ViewCount,
        p.AnswerCount,
        MIN(a.CreationDate) as first_answer_time,
        MAX(a.Score) as best_answer_score,
        COUNT(DISTINCT ph.UserId) as unique_editors,
        COUNT(DISTINCT c.UserId) as unique_commenters,
        EXTRACT(EPOCH FROM (MIN(a.CreationDate) - p.CreationDate))/3600 as hours_to_first_answer,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN EXTRACT(EPOCH FROM (acc.CreationDate - p.CreationDate))/86400
            ELSE NULL 
        END as days_to_acceptance
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    LEFT JOIN Posts acc ON acc.Id = p.AcceptedAnswerId
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
        AND p.CreationDate > NOW() - INTERVAL '2 years'
        AND p.Score > 10
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.AcceptedAnswerId, acc.CreationDate
),
badge_patterns AS (
    SELECT 
        b.Name as badge_name,
        b.Class,
        DATE_TRUNC('month', b.Date) as award_month,
        COUNT(DISTINCT b.UserId) as recipients,
        AVG(u.Reputation) as avg_recipient_reputation,
        STDDEV(u.Reputation) as stddev_reputation,
        LAG(COUNT(DISTINCT b.UserId), 1) OVER (PARTITION BY b.Name ORDER BY DATE_TRUNC('month', b.Date)) as prev_month_recipients,
        LAG(COUNT(DISTINCT b.UserId), 12) OVER (PARTITION BY b.Name ORDER BY DATE_TRUNC('month', b.Date)) as year_ago_recipients
    FROM Badges b
    INNER JOIN Users u ON u.Id = b.UserId
    WHERE b.Date > NOW() - INTERVAL '3 years'
    GROUP BY b.Name, b.Class, DATE_TRUNC('month', b.Date)
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    ue.expert_tags,
    ue.total_answers,
    ROUND(ue.avg_answer_score::numeric, 2) as avg_answer_score,
    ue.accepted_answers,
    ROUND(100.0 * ue.accepted_answers / ue.total_answers, 2) as acceptance_rate,
    COUNT(DISTINCT ql.Id) as high_quality_questions_answered,
    ROUND(AVG(ql.hours_to_first_answer)::numeric, 2) as avg_hours_to_first_answer,
    ROUND(AVG(ql.days_to_acceptance)::numeric, 2) as avg_days_to_acceptance,
    COUNT(DISTINCT bp.badge_name) as unique_badges_earned,
    MAX(bp.award_month) as most_recent_badge_month,
    SUM(CASE WHEN bp.Class = 1 THEN 1 ELSE 0 END) as gold_badges,
    SUM(CASE WHEN bp.Class = 2 THEN 1 ELSE 0 END) as silver_badges,
    SUM(CASE WHEN bp.Class = 3 THEN 1 ELSE 0 END) as bronze_badges,
    ROUND(AVG(ql.question_score)::numeric, 2) as avg_question_score_answered,
    ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY ql.ViewCount)::numeric, 0) as p90_question_views,
    DENSE_RANK() OVER (ORDER BY ue.Reputation DESC) as reputation_rank,
    DENSE_RANK() OVER (ORDER BY ue.accepted_answers DESC) as accepted_answers_rank,
    DENSE_RANK() OVER (ORDER BY ue.avg_answer_score DESC) as avg_score_rank
FROM user_expertise ue
LEFT JOIN Posts p ON p.OwnerUserId = ue.UserId AND p.PostTypeId = 2
LEFT JOIN question_lifecycle ql ON ql.Id = p.ParentId
LEFT JOIN Badges b ON b.UserId = ue.UserId
LEFT JOIN badge_patterns bp ON bp.badge_name = b.Name AND bp.award_month = DATE_TRUNC('month', b.Date)
GROUP BY 
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.expert_tags,
    ue.total_answers,
    ue.avg_answer_score,
    ue.accepted_answers,
    ue.median_score
HAVING COUNT(DISTINCT ql.Id) > 10
ORDER BY 
    ue.Reputation DESC,
    ue.accepted_answers DESC,
    ue.avg_answer_score DESC
LIMIT 100;
