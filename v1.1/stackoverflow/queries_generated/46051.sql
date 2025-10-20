-- {"query": "46051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 116994, "output_tokens": 95063} 

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
    HAVING COUNT(DISTINCT p.Id) >= 5
),
AnswerMetrics AS (
    SELECT 
        a.ParentId as question_id,
        a.Id as answer_id,
        a.OwnerUserId as answerer_id,
        a.Score as answer_score,
        a.CreationDate as answer_date,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as upvotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as downvotes,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as answer_rank
    FROM Posts a
    LEFT JOIN Comments c ON c.PostId = a.Id
    LEFT JOIN Votes v ON v.PostId = a.Id AND v.VoteTypeId IN (2, 3)
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId, a.Id, a.OwnerUserId, a.Score, a.CreationDate
),
QuestionEngagement AS (
    SELECT 
        q.Id as question_id,
        q.OwnerUserId,
        q.Title,
        q.Tags,
        q.Score as question_score,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        COUNT(DISTINCT ph.Id) as edit_count,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN ph.Id END) as close_reopen_count,
        MAX(CASE WHEN am.answer_rank = 1 THEN am.answer_score END) as top_answer_score,
        MAX(CASE WHEN am.answer_rank = 1 THEN am.comment_count END) as top_answer_comments,
        COUNT(DISTINCT am.answer_id) as total_answers,
        AVG(am.answer_score) as avg_answer_score
    FROM Posts q
    LEFT JOIN PostHistory ph ON ph.PostId = q.Id AND ph.PostHistoryTypeId IN (4, 5, 6, 10, 11)
    LEFT JOIN AnswerMetrics am ON am.question_id = q.Id
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= TIMESTAMP '2020-01-01'
        AND q.OwnerUserId IS NOT NULL
    GROUP BY q.Id, q.OwnerUserId, q.Title, q.Tags, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(DISTINCT b.Id) as total_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as gold_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as silver_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as bronze_badges,
        COUNT(DISTINCT CASE WHEN b.TagBased = 1 THEN b.Id END) as tag_based_badges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT 
    u.Id as user_id,
    u.DisplayName,
    u.Reputation,
    u.Location,
    tqa.question_count,
    tqa.avg_score as avg_question_score,
    tqa.total_views,
    COALESCE(ubs.total_badges, 0) as total_badges,
    COALESCE(ubs.gold_badges, 0) as gold_badges,
    COALESCE(ubs.silver_badges, 0) as silver_badges,
    qe.question_id,
    qe.Title as question_title,
    qe.question_score,
    qe.ViewCount as question_views,
    qe.edit_count,
    qe.close_reopen_count,
    qe.total_answers,
    COALESCE(qe.avg_answer_score, 0) as avg_answer_score,
    COALESCE(qe.top_answer_score, 0) as top_answer_score,
    COALESCE(qe.top_answer_comments, 0) as top_answer_comments,
    COUNT(DISTINCT pl.RelatedPostId) as related_posts_count,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) as duplicate_links,
    EXTRACT(EPOCH FROM (MAX(qe.ViewCount::numeric) / NULLIF(qe.total_answers, 0))) as views_per_answer_ratio
FROM TopQuestionAuthors tqa
INNER JOIN Users u ON u.Id = tqa.OwnerUserId
INNER JOIN QuestionEngagement qe ON qe.OwnerUserId = tqa.OwnerUserId
LEFT JOIN UserBadgeStats ubs ON ubs.UserId = u.Id
LEFT JOIN PostLinks pl ON pl.PostId = qe.question_id
WHERE qe.question_score >= 10
    AND qe.ViewCount >= 1000
    AND u.Reputation >= 500
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location,
    tqa.question_count, tqa.avg_score, tqa.total_views,
    ubs.total_badges, ubs.gold_badges, ubs.silver_badges,
    qe.question_id, qe.Title, qe.question_score, qe.ViewCount,
    qe.edit_count, qe.close_reopen_count, qe.total_answers,
    qe.avg_answer_score, qe.top_answer_score, qe.top_answer_comments
HAVING COUNT(DISTINCT pl.RelatedPostId) >= 2
ORDER BY 
    tqa.total_views DESC,
    qe.question_score DESC,
    qe.total_answers DESC
LIMIT 500;
