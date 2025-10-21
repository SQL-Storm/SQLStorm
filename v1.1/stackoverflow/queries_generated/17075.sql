-- {"query": "17075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2315}

WITH user_activity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answer_count,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) as avg_post_score,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '|') FILTER (WHERE p.Tags IS NOT NULL) as all_tags,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as reputation_rank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as activity_rank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_metrics AS (
    SELECT 
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) as gold_badges,
        COUNT(*) FILTER (WHERE Class = 2) as silver_badges,
        COUNT(*) FILTER (WHERE Class = 3) as bronze_badges,
        MAX(Date) as last_badge_date,
        STRING_AGG(CASE WHEN Class = 1 THEN Name END, ', ' ORDER BY Date DESC) as gold_badge_names
    FROM Badges
    WHERE Date >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY UserId
),
question_performance AS (
    SELECT 
        q.Id as QuestionId,
        q.OwnerUserId,
        q.Score as question_score,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        COALESCE(q.ClosedDate IS NOT NULL, FALSE) as is_closed,
        MAX(a.Score) as best_answer_score,
        AVG(a.Score) as avg_answer_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) as median_answer_score,
        COUNT(DISTINCT a.OwnerUserId) as unique_answerers,
        MIN(a.CreationDate) - q.CreationDate as time_to_first_answer,
        CASE 
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 1
            WHEN q.ClosedDate IS NOT NULL THEN -1
            ELSE 0
        END as question_status,
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.PostId = q.Id 
            AND c.Score > 5
            AND c.Text NOT LIKE '%duplicate%') as high_score_comments
    FROM Posts q
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= CURRENT_DATE - INTERVAL '18 months'
        AND LENGTH(COALESCE(q.Title, '')) > 20
    GROUP BY q.Id, q.OwnerUserId, q.Score, q.ViewCount, q.AnswerCount, 
             q.FavoriteCount, q.ClosedDate, q.AcceptedAnswerId, q.CreationDate
),
edit_history AS (
    SELECT 
        ph.PostId,
        COUNT(*) as total_edits,
        COUNT(DISTINCT ph.UserId) as unique_editors,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (7,8,9) THEN 1 ELSE 0 END) as rollback_count,
        FIRST_VALUE(ph.UserId) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as last_editor_id,
        LAG(ph.Text, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) as previous_text,
        CASE 
            WHEN ph.Comment LIKE '%improve%' OR ph.Comment LIKE '%fix%' THEN 'improvement'
            WHEN ph.Comment LIKE '%typo%' OR ph.Comment LIKE '%grammar%' THEN 'minor'
            ELSE 'other'
        END as edit_type
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
        AND ph.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
)
SELECT 
    ua.DisplayName,
    ua.Reputation,
    ua.reputation_rank,
    ua.activity_rank,
    COALESCE(ua.question_count, 0) + COALESCE(ua.answer_count, 0) as total_posts,
    ROUND(ua.avg_post_score::numeric, 2) as avg_post_score,
    COALESCE(bm.gold_badges, 0) as gold_badges,
    COALESCE(bm.silver_badges, 0) as silver_badges,
    COALESCE(bm.bronze_badges, 0) as bronze_badges,
    SUBSTRING(COALESCE(bm.gold_badge_names, 'None'), 1, 100) as recent_gold_badges,
    ROUND(AVG(qp.question_score)::numeric, 2) as avg_question_score,
    ROUND(AVG(qp.best_answer_score)::numeric, 2) as avg_best_answer_score,
    COUNT(DISTINCT qp.QuestionId) as questions_asked,
    SUM(CASE WHEN qp.question_status = 1 THEN 1 ELSE 0 END) as accepted_questions,
    SUM(CASE WHEN qp.question_status = -1 THEN 1 ELSE 0 END) as closed_questions,
    ROUND(AVG(EXTRACT(EPOCH FROM qp.time_to_first_answer)/3600)::numeric, 2) as avg_hours_to_first_answer,
    ROUND(AVG(qp.ViewCount)::numeric, 0) as avg_view_count,
    SUM(qp.high_score_comments) as total_high_score_comments,
    COUNT(DISTINCT eh.PostId) as edited_posts,
    SUM(eh.rollback_count) as total_rollbacks,
    CASE 
        WHEN ua.Reputation > 10000 AND COALESCE(bm.gold_badges, 0) > 5 THEN 'Elite'
        WHEN ua.Reputation > 5000 OR COALESCE(bm.gold_badges, 0) > 2 THEN 'Expert'
        WHEN ua.Reputation > 1000 OR COALESCE(bm.silver_badges, 0) > 10 THEN 'Advanced'
        ELSE 'Regular'
    END as user_tier,
    COALESCE(
        (SELECT STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName)
         FROM Tags t
         WHERE ua.all_tags LIKE '%' || t.TagName || '%'
            AND t.Count > 1000
         LIMIT 5),
        'No popular tags'
    ) as popular_tags_used,
    EXISTS (
        SELECT 1 
        FROM Votes v 
        WHERE v.UserId = ua.Id 
            AND v.VoteTypeId = 8
            AND v.BountyAmount IS NOT NULL
    ) as has_offered_bounty,
    (SELECT COUNT(DISTINCT pl.RelatedPostId)
     FROM PostLinks pl
     INNER JOIN Posts p ON pl.PostId = p.Id
     WHERE p.OwnerUserId = ua.Id
        AND pl.LinkTypeId = 3) as duplicate_questions_count
FROM user_activity ua
LEFT JOIN badge_metrics bm ON ua.Id = bm.UserId
LEFT JOIN question_performance qp ON ua.Id = qp.OwnerUserId
LEFT JOIN edit_history eh ON qp.QuestionId = eh.PostId
WHERE ua.post_count > 0
    AND (bm.gold_badges > 0 OR bm.silver_badges > 5 OR ua.Reputation > 5000)
GROUP BY 
    ua.Id, ua.DisplayName, ua.Reputation, ua.reputation_rank, ua.activity_rank,
    ua.question_count, ua.answer_count, ua.avg_post_score, ua.all_tags,
    bm.gold_badges, bm.silver_badges, bm.bronze_badges, bm.gold_badge_names
HAVING COUNT(DISTINCT qp.QuestionId) > 0 OR ua.answer_count > 10
ORDER BY 
    ua.reputation_rank ASC,
    COALESCE(bm.gold_badges, 0) DESC,
    avg_question_score DESC NULLS LAST
LIMIT 100;
