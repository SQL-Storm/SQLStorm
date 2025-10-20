-- {"query": "46087.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 199578, "output_tokens": 160207} 
WITH high_reputation_users AS (
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
question_stats AS (
    SELECT 
        p.Id as question_id,
        p.OwnerUserId,
        p.Score as question_score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        COALESCE(p.AcceptedAnswerId, 0) as has_accepted_answer,
        COUNT(DISTINCT v.Id) as vote_count,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT pl.RelatedPostId) as link_count,
        AVG(ans.Score) as avg_answer_score,
        MAX(ans.Score) as max_answer_score,
        STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) as tag_list
    FROM Posts p
    INNER JOIN high_reputation_users hru ON p.OwnerUserId = hru.Id
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 1
    LEFT JOIN Posts ans ON p.Id = ans.ParentId AND ans.PostTypeId = 2
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag_name
    ) pt ON TRUE
    LEFT JOIN Tags t ON pt.tag_name = t.TagName
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '2 years'
        AND p.Score >= 5
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.AcceptedAnswerId
),
edit_activity AS (
    SELECT 
        ph.PostId,
        COUNT(*) as edit_count,
        COUNT(DISTINCT ph.UserId) as unique_editors,
        MAX(ph.CreationDate) as last_edit_date,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) as substantive_edits
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    GROUP BY ph.PostId
),
user_engagement_metrics AS (
    SELECT 
        hru.Id as user_id,
        hru.DisplayName,
        hru.Reputation,
        hru.badge_count,
        hru.gold_badges,
        COUNT(DISTINCT qs.question_id) as question_count,
        AVG(qs.question_score) as avg_question_score,
        SUM(qs.ViewCount) as total_views,
        AVG(qs.AnswerCount) as avg_answers_received,
        SUM(qs.vote_count) as total_votes,
        AVG(qs.avg_answer_score) as avg_of_avg_answer_scores,
        COUNT(DISTINCT CASE WHEN qs.has_accepted_answer > 0 THEN qs.question_id END) as questions_with_accepted_answer,
        AVG(ea.edit_count) as avg_edits_per_question,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qs.question_score) as median_question_score
    FROM high_reputation_users hru
    LEFT JOIN question_stats qs ON hru.Id = qs.OwnerUserId
    LEFT JOIN edit_activity ea ON qs.question_id = ea.PostId
    GROUP BY hru.Id, hru.DisplayName, hru.Reputation, hru.badge_count, hru.gold_badges
    HAVING COUNT(DISTINCT qs.question_id) > 0
)
SELECT 
    uem.user_id,
    uem.DisplayName,
    uem.Reputation,
    uem.badge_count,
    uem.gold_badges,
    uem.question_count,
    ROUND(uem.avg_question_score, 2) as avg_question_score,
    uem.total_views,
    ROUND(uem.avg_answers_received, 2) as avg_answers_received,
    uem.total_votes,
    ROUND(uem.avg_of_avg_answer_scores, 2) as avg_of_avg_answer_scores,
    uem.questions_with_accepted_answer,
    ROUND(CAST(uem.questions_with_accepted_answer AS NUMERIC) / NULLIF(uem.question_count, 0) * 100, 2) as acceptance_rate,
    ROUND(uem.avg_edits_per_question, 2) as avg_edits_per_question,
    uem.median_question_score,
    RANK() OVER (ORDER BY uem.avg_question_score DESC) as score_rank,
    RANK() OVER (ORDER BY uem.total_views DESC) as views_rank,
    DENSE_RANK() OVER (ORDER BY uem.badge_count DESC) as badge_rank,
    ROW_NUMBER() OVER (PARTITION BY CASE WHEN uem.Reputation > 50000 THEN 'elite' ELSE 'regular' END ORDER BY uem.total_votes DESC) as category_position
FROM user_engagement_metrics uem
WHERE uem.total_views > 10000
ORDER BY uem.avg_question_score DESC, uem.total_votes DESC
LIMIT 100;