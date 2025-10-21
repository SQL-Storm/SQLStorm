-- {"query": "46097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 222518, "output_tokens": 178476} 

WITH user_expertise AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answer_count,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) as avg_answer_score,
        COUNT(DISTINCT b.Id) as badge_count,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as gold_badges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) >= 10
),
question_metrics AS (
    SELECT 
        q.Id as question_id,
        q.Title,
        q.Score as question_score,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        COALESCE(a.Id, 0) as accepted_answer_id,
        COALESCE(a.Score, 0) as accepted_answer_score,
        q.CreationDate as q_created,
        COUNT(DISTINCT c.Id) as total_comments,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as upvotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as downvotes,
        COUNT(DISTINCT ph.Id) as edit_history_count,
        string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><') as tag_array
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    LEFT JOIN Comments c ON q.Id = c.PostId
    LEFT JOIN Votes v ON q.Id = v.PostId
    LEFT JOIN PostHistory ph ON q.Id = ph.PostId
    WHERE q.PostTypeId = 1 
        AND q.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND q.Score >= 5
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount, 
             a.Id, a.Score, q.CreationDate, q.Tags
),
tag_performance AS (
    SELECT 
        unnest(qm.tag_array) as tag_name,
        COUNT(DISTINCT qm.question_id) as questions_with_tag,
        AVG(qm.question_score) as avg_tag_score,
        SUM(qm.ViewCount) as total_views,
        AVG(qm.AnswerCount) as avg_answers_per_question
    FROM question_metrics qm
    GROUP BY unnest(qm.tag_array)
    HAVING COUNT(DISTINCT qm.question_id) >= 20
),
answer_quality AS (
    SELECT 
        a.Id as answer_id,
        a.ParentId as question_id,
        a.OwnerUserId,
        a.Score as answer_score,
        a.CreationDate as answer_created,
        q.CreationDate as question_created,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 as hours_to_answer,
        LENGTH(a.Body) as answer_length,
        COUNT(DISTINCT ac.Id) as answer_comments,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END as is_accepted,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate) as answer_rank
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    LEFT JOIN Comments ac ON a.Id = ac.PostId
    WHERE a.PostTypeId = 2 
        AND a.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND a.Score >= 0
    GROUP BY a.Id, a.ParentId, a.OwnerUserId, a.Score, a.CreationDate, 
             q.CreationDate, q.AcceptedAnswerId, a.Body
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    ue.question_count,
    ue.answer_count,
    ROUND(ue.avg_answer_score::numeric, 2) as avg_answer_score,
    ue.badge_count,
    ue.gold_badges,
    COUNT(DISTINCT aq.answer_id) as quality_answers,
    AVG(aq.answer_score) as avg_quality_score,
    AVG(aq.hours_to_answer) as avg_response_time_hours,
    COUNT(DISTINCT CASE WHEN aq.is_accepted = 1 THEN aq.answer_id END) as accepted_answers,
    COUNT(DISTINCT CASE WHEN aq.answer_rank = 1 THEN aq.answer_id END) as first_answers,
    AVG(qm.question_score) as avg_related_question_score,
    AVG(qm.ViewCount) as avg_question_views,
    STRING_AGG(DISTINCT tp.tag_name, ', ' ORDER BY tp.questions_with_tag DESC) 
        FILTER (WHERE tp.avg_tag_score > 5) as top_performing_tags,
    ROUND(AVG(tp.avg_tag_score)::numeric, 2) as avg_tag_performance,
    SUM(CASE WHEN aq.answer_length > 1000 THEN 1 ELSE 0 END) as detailed_answers,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY aq.answer_score) as median_answer_score
FROM user_expertise ue
INNER JOIN answer_quality aq ON ue.Id = aq.OwnerUserId
INNER JOIN question_metrics qm ON aq.question_id = qm.question_id
LEFT JOIN tag_performance tp ON tp.tag_name = ANY(qm.tag_array)
WHERE aq.answer_score >= 1
GROUP BY ue.Id, ue.DisplayName, ue.Reputation, ue.question_count, ue.answer_count, 
         ue.avg_answer_score, ue.badge_count, ue.gold_badges
HAVING COUNT(DISTINCT aq.answer_id) >= 5
    AND AVG(aq.answer_score) >= 2
ORDER BY avg_quality_score DESC, accepted_answers DESC, ue.Reputation DESC
LIMIT 100;
