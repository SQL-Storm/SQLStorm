-- {"query": "47047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1849}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) as direct_questions,
        t.WikiPostId,
        1 as level
    FROM Tags t
    INNER JOIN Posts pt ON pt.Tags LIKE '%<' || t.TagName || '>%'
    WHERE t.Count > 1000
        AND pt.PostTypeId = 1
    GROUP BY t.Id, t.TagName, t.WikiPostId
),
user_expertise AS (
    SELECT 
        u.Id as user_id,
        u.DisplayName,
        u.Reputation,
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') as tag_array,
        COUNT(DISTINCT p.Id) as answer_count,
        SUM(p.Score) as total_score,
        AVG(p.Score) as avg_score,
        MAX(p.Score) as best_answer,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score,
        COUNT(DISTINCT CASE WHEN p.Id = q.AcceptedAnswerId THEN p.Id END) as accepted_answers,
        COUNT(DISTINCT b.Id) as badge_count,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as gold_badges
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id
    INNER JOIN Posts q ON q.Id = p.ParentId
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.TagBased = true
    WHERE p.PostTypeId = 2
        AND p.Score > 0
        AND u.Reputation > 5000
        AND p.CreationDate >= NOW() - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, p.Tags
),
post_activity AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        COUNT(DISTINCT ph.Id) as edit_count,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.Id END) as content_edits,
        COUNT(DISTINCT c.Id) as comment_count,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) as downvotes,
        MIN(ph.CreationDate) as first_edit,
        MAX(ph.CreationDate) as last_edit,
        EXTRACT(EPOCH FROM (MAX(ph.CreationDate) - p.CreationDate))/3600 as hours_to_last_edit,
        COUNT(DISTINCT pl.RelatedPostId) as linked_posts,
        ARRAY_AGG(DISTINCT ph.UserId) FILTER (WHERE ph.UserId != p.OwnerUserId) as editor_ids
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    WHERE p.PostTypeId = 1
        AND p.Score >= 10
        AND p.ViewCount > 1000
        AND p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate
),
community_impact AS (
    SELECT 
        pa.*,
        u.DisplayName as author_name,
        u.Reputation as author_reputation,
        COUNT(DISTINCT a.OwnerUserId) as unique_answerers,
        AVG(au.Reputation) as avg_answerer_reputation,
        SUM(a.Score) as total_answer_score,
        STDDEV(a.Score) as answer_score_stddev,
        MAX(a.Score) as best_answer_score,
        MIN(EXTRACT(EPOCH FROM (a.CreationDate - pa.CreationDate))/60) as fastest_answer_minutes,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY a.Score) as p90_answer_score
    FROM post_activity pa
    INNER JOIN Users u ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = pa.Id)
    LEFT JOIN Posts a ON a.ParentId = pa.Id AND a.PostTypeId = 2
    LEFT JOIN Users au ON au.Id = a.OwnerUserId
    GROUP BY pa.Id, pa.Title, pa.Score, pa.ViewCount, pa.AnswerCount, 
             pa.CreationDate, pa.edit_count, pa.content_edits, pa.comment_count,
             pa.upvotes, pa.downvotes, pa.first_edit, pa.last_edit, 
             pa.hours_to_last_edit, pa.linked_posts, pa.editor_ids,
             u.DisplayName, u.Reputation
)
SELECT 
    ci.Title,
    ci.author_name,
    ci.Score as question_score,
    ci.ViewCount as views,
    ci.AnswerCount as answers,
    ci.unique_answerers,
    ROUND(ci.avg_answerer_reputation::numeric, 0) as avg_answerer_rep,
    ci.total_answer_score,
    ci.best_answer_score,
    ROUND(ci.answer_score_stddev::numeric, 2) as answer_variation,
    ci.fastest_answer_minutes,
    ci.edit_count,
    ci.comment_count,
    ci.upvotes,
    ci.downvotes,
    ROUND((ci.upvotes::numeric / NULLIF(ci.upvotes + ci.downvotes, 0)) * 100, 1) as upvote_ratio,
    ci.linked_posts,
    ROUND(ci.hours_to_last_edit::numeric, 1) as hours_to_stabilize,
    ROUND((ci.Score::numeric / NULLIF(ci.ViewCount, 0)) * 1000, 2) as score_per_1k_views,
    ROUND((ci.AnswerCount::numeric / NULLIF(ci.unique_answerers, 0)), 2) as answers_per_user,
    ci.p90_answer_score,
    CASE 
        WHEN ci.Score > 100 AND ci.ViewCount > 10000 THEN 'Viral'
        WHEN ci.Score > 50 AND ci.ViewCount > 5000 THEN 'Popular'
        WHEN ci.Score > 20 THEN 'Well-Received'
        ELSE 'Standard'
    END as impact_category,
    DENSE_RANK() OVER (ORDER BY ci.Score * LOG(ci.ViewCount + 1) DESC) as impact_rank
FROM community_impact ci
WHERE ci.unique_answerers >= 3
ORDER BY impact_rank
LIMIT 100;
