WITH TopQuestionAuthors AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS question_count,
        AVG(p.Score) AS avg_score,
        SUM(p.ViewCount) AS total_views
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.OwnerUserId IS NOT NULL
        AND p.CreationDate >= CAST(CAST('2024-10-01' AS date) - INTERVAL '2 years' AS date)
    GROUP BY p.OwnerUserId
    HAVING COUNT(DISTINCT p.Id) >= 10
),
AnswerMetrics AS (
    SELECT 
        a.OwnerUserId AS answerer_id,
        q.OwnerUserId AS questioner_id,
        COUNT(DISTINCT a.Id) AS answer_count,
        AVG(a.Score) AS avg_answer_score,
        COUNT(DISTINCT CASE WHEN q.AcceptedAnswerId = a.Id THEN a.Id END) AS accepted_count,
        STRING_AGG(DISTINCT SUBSTRING(q.Tags FROM 2 FOR 50), '|') AS common_tags
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
        COUNT(DISTINCT b.Id) AS badge_count,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS gold_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS silver_badges,
        COUNT(DISTINCT v.Id) AS vote_count,
        MAX(u.LastAccessDate) AS last_active
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
        COALESCE(c.comment_interactions, 0) AS comment_count,
        COALESCE(ph.edit_count, 0) AS edit_count
    FROM TopQuestionAuthors tqa
    INNER JOIN AnswerMetrics am ON tqa.OwnerUserId = am.questioner_id
    LEFT JOIN (
        SELECT c1.UserId, p1.OwnerUserId AS post_owner, COUNT(DISTINCT c1.Id) AS comment_interactions
        FROM Comments c1
        INNER JOIN Posts p1 ON c1.PostId = p1.Id
        GROUP BY c1.UserId, p1.OwnerUserId
    ) c ON c.post_owner = tqa.OwnerUserId AND c.UserId = am.answerer_id
    LEFT JOIN (
        SELECT ph1.UserId, p2.OwnerUserId AS post_owner, COUNT(DISTINCT ph1.Id) AS edit_count
        FROM PostHistory ph1
        INNER JOIN Posts p2 ON ph1.PostId = p2.Id
        WHERE ph1.PostHistoryTypeId IN (4, 5, 6)
        GROUP BY ph1.UserId, p2.OwnerUserId
    ) ph ON ph.post_owner = tqa.OwnerUserId AND ph.UserId = am.answerer_id
)
SELECT 
    ue_q.DisplayName AS question_author,
    ue_q.Reputation AS question_author_reputation,
    ue_q.badge_count AS question_author_badges,
    ue_a.DisplayName AS top_answerer,
    ue_a.Reputation AS answerer_reputation,
    ue_a.gold_badges,
    ue_a.silver_badges,
    ci.question_count,
    ci.answer_count,
    ci.accepted_count,
    ROUND(CAST(ci.avg_answer_score AS numeric), 2) AS avg_answer_score,
    ROUND((CAST(ci.accepted_count AS numeric) / NULLIF(ci.answer_count, 0)) * 100, 2) AS acceptance_rate,
    ci.comment_count,
    ci.edit_count,
    ci.comment_count + ci.edit_count + ci.answer_count AS total_engagement_score,
    EXTRACT(DAY FROM (ue_a.last_active - ue_a.CreationDate)) AS answerer_tenure_days,
    RANK() OVER (PARTITION BY ci.OwnerUserId ORDER BY ci.answer_count DESC, ci.accepted_count DESC) AS answerer_rank
FROM ComplexInteractions ci
INNER JOIN UserEngagement ue_q ON ci.OwnerUserId = ue_q.Id
INNER JOIN UserEngagement ue_a ON ci.answerer_id = ue_a.Id
WHERE ci.answer_count >= 5
    AND ue_a.Reputation >= 5000
ORDER BY total_engagement_score DESC, ci.accepted_count DESC, ci.answer_count DESC
LIMIT 100;