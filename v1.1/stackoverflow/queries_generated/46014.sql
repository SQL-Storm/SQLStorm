-- {"query": "46014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 32116, "output_tokens": 25281} 

WITH high_value_users AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT b.Id) as badge_count,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as gold_badges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT b.Id) > 5
),
question_metrics AS (
    SELECT 
        p.Id as question_id,
        p.OwnerUserId,
        p.Score as q_score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate as q_creation_date,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as upvotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as downvotes,
        COUNT(DISTINCT ph.Id) as edit_count,
        STRING_AGG(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId::text END, ',') as duplicate_links
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND p.Score >= 5
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate
),
answer_quality AS (
    SELECT 
        a.ParentId as question_id,
        a.Id as answer_id,
        a.OwnerUserId as answerer_id,
        a.Score as answer_score,
        a.CreationDate as answer_date,
        CASE WHEN qm.question_id IS NOT NULL AND q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END as is_accepted,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as answer_rank
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    INNER JOIN question_metrics qm ON q.Id = qm.question_id
    WHERE a.PostTypeId = 2
        AND a.Score >= 0
),
tag_analysis AS (
    SELECT 
        UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag_name,
        p.Id as post_id,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
        AND p.Tags IS NOT NULL
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
),
user_tag_expertise AS (
    SELECT 
        ta.OwnerUserId,
        ta.tag_name,
        COUNT(DISTINCT ta.post_id) as posts_in_tag,
        AVG(qm.q_score) as avg_score_in_tag,
        SUM(qm.ViewCount) as total_views_in_tag
    FROM tag_analysis ta
    INNER JOIN question_metrics qm ON ta.post_id = qm.question_id
    WHERE ta.OwnerUserId IS NOT NULL
    GROUP BY ta.OwnerUserId, ta.tag_name
    HAVING COUNT(DISTINCT ta.post_id) >= 3
)
SELECT 
    hvu.DisplayName,
    hvu.Reputation,
    hvu.badge_count,
    hvu.gold_badges,
    COUNT(DISTINCT qm.question_id) as total_questions,
    ROUND(AVG(qm.q_score)::numeric, 2) as avg_question_score,
    SUM(qm.ViewCount) as total_question_views,
    COUNT(DISTINCT aq.answer_id) as total_answers,
    ROUND(AVG(aq.answer_score)::numeric, 2) as avg_answer_score,
    COUNT(DISTINCT CASE WHEN aq.is_accepted = 1 THEN aq.answer_id END) as accepted_answers,
    COUNT(DISTINCT CASE WHEN aq.answer_rank = 1 THEN aq.answer_id END) as top_ranked_answers,
    ROUND(AVG(qm.edit_count)::numeric, 2) as avg_edits_per_question,
    COUNT(DISTINCT ute.tag_name) as expertise_tags,
    MAX(ute.posts_in_tag) as max_posts_single_tag,
    STRING_AGG(DISTINCT ute.tag_name, ', ' ORDER BY ute.tag_name) FILTER (WHERE ute.posts_in_tag >= 5) as top_expertise_tags,
    ROUND(AVG(EXTRACT(EPOCH FROM (aq.answer_date - qm.q_creation_date)) / 3600)::numeric, 2) as avg_hours_to_answer,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qm.ViewCount) as median_question_views,
    ROUND((COUNT(DISTINCT aq.answer_id)::numeric / NULLIF(COUNT(DISTINCT qm.question_id), 0))::numeric, 2) as answer_to_question_ratio
FROM high_value_users hvu
LEFT JOIN question_metrics qm ON hvu.Id = qm.OwnerUserId
LEFT JOIN answer_quality aq ON hvu.Id = aq.answerer_id
LEFT JOIN user_tag_expertise ute ON hvu.Id = ute.OwnerUserId
GROUP BY hvu.Id, hvu.DisplayName, hvu.Reputation, hvu.badge_count, hvu.gold_badges
HAVING COUNT(DISTINCT qm.question_id) > 0 OR COUNT(DISTINCT aq.answer_id) > 0
ORDER BY 
    (COUNT(DISTINCT qm.question_id) * AVG(qm.q_score) + 
     COUNT(DISTINCT aq.answer_id) * AVG(aq.answer_score) + 
     hvu.Reputation * 0.1) DESC
LIMIT 100;
