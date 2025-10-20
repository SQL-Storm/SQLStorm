-- {"query": "47010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 22940, "output_tokens": 19548} 

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) as direct_questions,
        0 as level
    FROM Tags t
    JOIN Posts pt ON pt.Tags LIKE '%<' || t.TagName || '>%'
    WHERE pt.PostTypeId = 1
        AND t.Count > 1000
    GROUP BY t.Id, t.TagName
),
user_expertise AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        t.TagName,
        COUNT(DISTINCT p.Id) as answers_in_tag,
        SUM(p.Score) as total_score,
        AVG(p.Score) as avg_score,
        SUM(CASE WHEN p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) as accepted_answers,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) as tag_rank
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    JOIN Posts q ON q.Id = p.ParentId
    JOIN Tags t ON q.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 2
        AND u.Reputation > 5000
        AND p.Score > 0
        AND q.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, u.Reputation, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
question_lifecycle AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        EXTRACT(EPOCH FROM (COALESCE(first_answer.CreationDate, NOW()) - p.CreationDate))/3600 as hours_to_first_answer,
        EXTRACT(EPOCH FROM (COALESCE(accepted.CreationDate, NOW()) - p.CreationDate))/86400 as days_to_acceptance,
        edit_counts.edit_count,
        close_reopen.close_count,
        close_reopen.reopen_count,
        CASE 
            WHEN p.ViewCount > 10000 AND p.Score > 50 THEN 'High Impact'
            WHEN p.ViewCount > 1000 AND p.Score > 10 THEN 'Medium Impact'
            ELSE 'Low Impact'
        END as impact_category
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT MIN(a.CreationDate) as CreationDate
        FROM Posts a
        WHERE a.ParentId = p.Id AND a.PostTypeId = 2
    ) first_answer ON true
    LEFT JOIN LATERAL (
        SELECT MIN(ph.CreationDate) as CreationDate
        FROM PostHistory ph
        WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 1
    ) accepted ON true
    LEFT JOIN LATERAL (
        SELECT COUNT(*) as edit_count
        FROM PostHistory ph
        WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
    ) edit_counts ON true
    LEFT JOIN LATERAL (
        SELECT 
            SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) as close_count,
            SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) as reopen_count
        FROM PostHistory ph
        WHERE ph.PostId = p.Id
    ) close_reopen ON true
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
),
badge_patterns AS (
    SELECT 
        b.Name as badge_name,
        b.Class,
        DATE_TRUNC('month', b.Date) as award_month,
        COUNT(DISTINCT b.UserId) as recipients,
        AVG(u.Reputation) as avg_recipient_reputation,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY u.Reputation) as median_reputation,
        SUM(CASE WHEN b.TagBased = '1' THEN 1 ELSE 0 END) as tag_based_count
    FROM Badges b
    JOIN Users u ON u.Id = b.UserId
    WHERE b.Date >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY b.Name, b.Class, DATE_TRUNC('month', b.Date)
    HAVING COUNT(DISTINCT b.UserId) >= 5
),
voting_patterns AS (
    SELECT 
        DATE_TRUNC('week', v.CreationDate) as vote_week,
        vt.Name as vote_type,
        COUNT(*) as vote_count,
        COUNT(DISTINCT v.UserId) as unique_voters,
        COUNT(DISTINCT v.PostId) as unique_posts,
        AVG(CASE WHEN v.BountyAmount IS NOT NULL THEN v.BountyAmount ELSE 0 END) as avg_bounty
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '6 months'
    GROUP BY DATE_TRUNC('week', v.CreationDate), vt.Name
)
SELECT 
    th.TagName,
    th.direct_questions,
    ue.DisplayName as top_expert,
    ue.Reputation as expert_reputation,
    ue.answers_in_tag,
    ue.total_score as expert_total_score,
    ue.accepted_answers,
    ROUND(ue.accepted_answers::numeric / NULLIF(ue.answers_in_tag, 0) * 100, 2) as acceptance_rate,
    ql.impact_category,
    COUNT(DISTINCT ql.Id) as questions_in_category,
    ROUND(AVG(ql.hours_to_first_answer), 2) as avg_hours_to_first_answer,
    ROUND(AVG(ql.days_to_acceptance), 2) as avg_days_to_acceptance,
    ROUND(AVG(ql.edit_count), 2) as avg_edits_per_question,
    STRING_AGG(DISTINCT bp.badge_name || ' (' || bp.recipients || ')', ', ' ORDER BY bp.recipients DESC) as related_badges,
    MAX(vp.vote_count) as peak_weekly_votes,
    ROUND(AVG(vp.vote_count), 2) as avg_weekly_votes
FROM tag_hierarchy th
LEFT JOIN user_expertise ue ON ue.TagName = th.TagName AND ue.tag_rank = 1
LEFT JOIN question_lifecycle ql ON ql.Id IN (
    SELECT p.Id 
    FROM Posts p 
    WHERE p.Tags LIKE '%<' || th.TagName || '>%' 
        AND p.PostTypeId = 1
    LIMIT 100
)
LEFT JOIN badge_patterns bp ON bp.badge_name LIKE '%' || th.TagName || '%'
LEFT JOIN voting_patterns vp ON vp.vote_type = 'UpMod'
WHERE th.direct_questions > 100
GROUP BY 
    th.TagName,
    th.direct_questions,
    ue.DisplayName,
    ue.Reputation,
    ue.answers_in_tag,
    ue.total_score,
    ue.accepted_answers,
    ql.impact_category
ORDER BY 
    th.direct_questions DESC,
    ue.total_score DESC NULLS LAST
LIMIT 50;
