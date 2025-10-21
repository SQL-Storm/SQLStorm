-- {"query": "46099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 227106, "output_tokens": 181517} 

WITH TopQuestionAuthors AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) as question_count,
        AVG(p.Score) as avg_score,
        SUM(p.ViewCount) as total_views
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.OwnerUserId IS NOT NULL
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY p.OwnerUserId
    HAVING COUNT(DISTINCT p.Id) >= 10
),
AnswerMetrics AS (
    SELECT 
        a.OwnerUserId as answerer_id,
        q.OwnerUserId as questioner_id,
        COUNT(DISTINCT a.Id) as answer_count,
        AVG(a.Score) as avg_answer_score,
        COUNT(DISTINCT CASE WHEN q.AcceptedAnswerId = a.Id THEN a.Id END) as accepted_count,
        STRING_AGG(DISTINCT SUBSTRING(q.Tags, 2, 50), '|') as common_tags
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 
        AND q.PostTypeId = 1
        AND a.OwnerUserId IS NOT NULL
        AND q.OwnerUserId IS NOT NULL
    GROUP BY a.OwnerUserId, q.OwnerUserId
    HAVING COUNT(DISTINCT a.Id) >= 3
),
UserEngagement AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT b.Id) as badge_count,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as gold_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as silver_badges,
        COUNT(DISTINCT v.Id) as vote_count,
        MAX(u.LastAccessDate) as last_active
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3, 8)
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
ComplexInteractions AS (
    SELECT 
        tqa.OwnerUserId,
        am.answerer_id,
        tqa.question_count,
        am.answer_count,
        am.accepted_count,
        am.avg_answer_score,
        COALESCE(c.comment_interactions, 0) as comment_count,
        COALESCE(ph.edit_count, 0) as edit_count
    FROM TopQuestionAuthors tqa
    INNER JOIN AnswerMetrics am ON tqa.OwnerUserId = am.questioner_id
    LEFT JOIN LATERAL (
        SELECT COUNT(DISTINCT c1.Id) as comment_interactions
        FROM Comments c1
        INNER JOIN Posts p1 ON c1.PostId = p1.Id
        WHERE p1.OwnerUserId = tqa.OwnerUserId
            AND c1.UserId = am.answerer_id
    ) c ON true
    LEFT JOIN LATERAL (
        SELECT COUNT(DISTINCT ph1.Id) as edit_count
        FROM PostHistory ph1
        INNER JOIN Posts p2 ON ph1.PostId = p2.Id
        WHERE p2.OwnerUserId = tqa.OwnerUserId
            AND ph1.UserId = am.answerer_id
            AND ph1.PostHistoryTypeId IN (4, 5, 6)
    ) ph ON true
)
SELECT 
    ue_q.DisplayName as question_author,
    ue_q.Reputation as question_author_reputation,
    ue_q.badge_count as question_author_badges,
    ue_a.DisplayName as top_answerer,
    ue_a.Reputation as answerer_reputation,
    ue_a.gold_badges,
    ue_a.silver_badges,
    ci.question_count,
    ci.answer_count,
    ci.accepted_count,
    ROUND(ci.avg_answer_score::numeric, 2) as avg_answer_score,
    ROUND((ci.accepted_count::numeric / NULLIF(ci.answer_count, 0)) * 100, 2) as acceptance_rate,
    ci.comment_count,
    ci.edit_count,
    ci.comment_count + ci.edit_count + ci.answer_count as total_engagement_score,
    EXTRACT(DAYS FROM (ue_a.last_active - ue_a.CreationDate)) as answerer_tenure_days,
    RANK() OVER (PARTITION BY ci.OwnerUserId ORDER BY ci.answer_count DESC, ci.accepted_count DESC) as answerer_rank
FROM ComplexInteractions ci
INNER JOIN UserEngagement ue_q ON ci.OwnerUserId = ue_q.Id
INNER JOIN UserEngagement ue_a ON ci.answerer_id = ue_a.Id
WHERE ci.answer_count >= 5
    AND ue_a.Reputation >= 5000
ORDER BY total_engagement_score DESC, ci.accepted_count DESC, ci.answer_count DESC
LIMIT 100;
