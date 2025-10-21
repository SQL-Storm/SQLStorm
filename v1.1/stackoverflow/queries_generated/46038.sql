-- {"query": "46038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1557}

WITH TopQuestionAuthors AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) as question_count,
        AVG(p.Score) as avg_score,
        SUM(p.ViewCount) as total_views
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.OwnerUserId IS NOT NULL
        AND p.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY p.OwnerUserId
    HAVING COUNT(DISTINCT p.Id) >= 10
),
AnswerMetrics AS (
    SELECT 
        a.ParentId as question_id,
        a.Id as answer_id,
        a.OwnerUserId as answerer_id,
        a.Score as answer_score,
        a.CreationDate as answer_date,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as upvote_count,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as answer_rank
    FROM Posts a
    LEFT JOIN Comments c ON a.Id = c.PostId
    LEFT JOIN Votes v ON a.Id = v.PostId
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId, a.Id, a.OwnerUserId, a.Score, a.CreationDate
),
QuestionEngagement AS (
    SELECT 
        q.Id as question_id,
        q.OwnerUserId as asker_id,
        q.Score as question_score,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        COALESCE(am.answer_score, 0) as best_answer_score,
        am.answerer_id as best_answerer_id,
        am.comment_count as best_answer_comments,
        COUNT(DISTINCT pl.RelatedPostId) as linked_questions,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.TagBased = 1) as tag_badges_earned,
        STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) as all_tags
    FROM Posts q
    INNER JOIN TopQuestionAuthors tqa ON q.OwnerUserId = tqa.OwnerUserId
    LEFT JOIN AnswerMetrics am ON q.Id = am.question_id AND am.answer_rank = 1
    LEFT JOIN PostLinks pl ON q.Id = pl.PostId AND pl.LinkTypeId = 1
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Date >= q.CreationDate AND b.Date <= q.CreationDate + INTERVAL '30 days'
    LEFT JOIN LATERAL (
        SELECT t.TagName
        FROM unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as tag
        INNER JOIN Tags t ON t.TagName = tag
    ) t ON true
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.OwnerUserId, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount, 
             am.answer_score, am.answerer_id, am.comment_count
),
UserInteractionNetwork AS (
    SELECT 
        qe.asker_id,
        qe.best_answerer_id,
        COUNT(DISTINCT qe.question_id) as interaction_count,
        AVG(qe.best_answer_score - qe.question_score) as avg_answer_advantage,
        SUM(qe.ViewCount) as total_interaction_views
    FROM QuestionEngagement qe
    WHERE qe.best_answerer_id IS NOT NULL
    GROUP BY qe.asker_id, qe.best_answerer_id
    HAVING COUNT(DISTINCT qe.question_id) >= 3
)
SELECT 
    u1.DisplayName as question_author,
    u1.Reputation as author_reputation,
    u2.DisplayName as frequent_answerer,
    u2.Reputation as answerer_reputation,
    uin.interaction_count,
    ROUND(uin.avg_answer_advantage, 2) as avg_answer_score_advantage,
    uin.total_interaction_views,
    COUNT(DISTINCT qe.question_id) as total_questions,
    ROUND(AVG(qe.question_score), 2) as avg_question_score,
    ROUND(AVG(qe.best_answer_score), 2) as avg_best_answer_score,
    ROUND(AVG(qe.ViewCount), 0) as avg_views_per_question,
    ROUND(AVG(qe.AnswerCount), 1) as avg_answers_per_question,
    SUM(qe.linked_questions) as total_linked_questions,
    SUM(qe.tag_badges_earned) as tag_badges_during_period,
    STRING_AGG(DISTINCT qe.all_tags, ' | ') as common_tags,
    RANK() OVER (ORDER BY uin.interaction_count DESC, uin.total_interaction_views DESC) as network_rank
FROM UserInteractionNetwork uin
INNER JOIN Users u1 ON uin.asker_id = u1.Id
INNER JOIN Users u2 ON uin.best_answerer_id = u2.Id
INNER JOIN QuestionEngagement qe ON qe.asker_id = uin.asker_id AND qe.best_answerer_id = uin.best_answerer_id
GROUP BY u1.Id, u1.DisplayName, u1.Reputation, u2.Id, u2.DisplayName, u2.Reputation,
         uin.interaction_count, uin.avg_answer_advantage, uin.total_interaction_views
HAVING AVG(qe.ViewCount) > 500
ORDER BY network_rank, uin.total_interaction_views DESC
LIMIT 100;
