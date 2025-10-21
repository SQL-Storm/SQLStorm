-- {"query": "47032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 2297}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT p.Id) as question_count,
        SUM(p.ViewCount) as total_views,
        AVG(p.Score) as avg_score,
        1 as level
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 1
        AND t.Count > 1000
    GROUP BY t.Id, t.TagName
),
user_expertise AS (
    SELECT 
        u.Id as user_id,
        u.DisplayName,
        u.Reputation,
        string_agg(DISTINCT substring(p.Tags, 2, length(p.Tags)-2), ', ') as expertise_tags,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) as questions_asked,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) as answers_given,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2 AND p.Score >= 10) as high_quality_answers,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) as gold_badges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) as silver_badges,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) FILTER (WHERE p.PostTypeId = 2) as median_answer_score,
        MAX(p.Score) FILTER (WHERE p.PostTypeId = 2) as best_answer_score,
        AVG(EXTRACT(EPOCH FROM (COALESCE(a.CreationDate, NOW()) - p.CreationDate))/3600) FILTER (WHERE p.PostTypeId = 1 AND a.Id IS NOT NULL) as avg_hours_to_accepted_answer
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Posts a ON a.Id = p.AcceptedAnswerId
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 5000
        AND u.LastAccessDate > NOW() - INTERVAL '180 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 50
),
post_quality_metrics AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        CASE 
            WHEN p.ViewCount > 0 THEN p.Score::FLOAT / p.ViewCount 
            ELSE 0 
        END as score_per_view,
        COUNT(DISTINCT ph.Id) as edit_count,
        COUNT(DISTINCT c.Id) as comment_count,
        AVG(c.Score) as avg_comment_score,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as upvote_count,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as downvote_count,
        COUNT(DISTINCT pl.Id) FILTER (WHERE pl.LinkTypeId = 1) as linked_post_count,
        COUNT(DISTINCT pl2.Id) FILTER (WHERE pl2.LinkTypeId = 1) as linking_post_count,
        EXTRACT(EPOCH FROM (COALESCE(p.ClosedDate, NOW()) - p.CreationDate))/86400 as days_until_closed,
        RANK() OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate) ORDER BY p.Score DESC) as monthly_rank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC NULLS LAST) as view_rank,
        NTILE(100) OVER (ORDER BY p.Score) as score_percentile
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    LEFT JOIN PostLinks pl2 ON pl2.RelatedPostId = p.Id
    WHERE p.PostTypeId = 1
        AND p.CreationDate > NOW() - INTERVAL '2 years'
        AND p.Score > 0
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.CreationDate, p.ClosedDate
),
temporal_patterns AS (
    SELECT 
        DATE_TRUNC('week', p.CreationDate) as week,
        EXTRACT(DOW FROM p.CreationDate) as day_of_week,
        EXTRACT(HOUR FROM p.CreationDate) as hour_of_day,
        COUNT(DISTINCT p.Id) as post_count,
        AVG(p.Score) as avg_score,
        AVG(p.ViewCount) as avg_views,
        STDDEV(p.Score) as score_stddev,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY p.Score) as q1_score,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY p.Score) as q3_score,
        COUNT(DISTINCT p.OwnerUserId) as unique_users,
        SUM(p.AnswerCount) as total_answers,
        AVG(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) as acceptance_rate
    FROM Posts p
    WHERE p.PostTypeId = 1
        AND p.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY DATE_TRUNC('week', p.CreationDate), EXTRACT(DOW FROM p.CreationDate), EXTRACT(HOUR FROM p.CreationDate)
)
SELECT 
    th.TagName,
    th.question_count,
    th.total_views,
    th.avg_score as tag_avg_score,
    ue.DisplayName as top_contributor,
    ue.Reputation,
    ue.gold_badges,
    ue.silver_badges,
    ue.high_quality_answers,
    ue.median_answer_score,
    ue.avg_hours_to_accepted_answer,
    pqm.Title as top_question_title,
    pqm.Score as top_question_score,
    pqm.ViewCount as top_question_views,
    pqm.score_per_view,
    pqm.edit_count,
    pqm.comment_count,
    pqm.upvote_count,
    pqm.downvote_count,
    pqm.linked_post_count,
    pqm.score_percentile,
    tp.week,
    tp.day_of_week,
    tp.hour_of_day,
    tp.post_count as temporal_post_count,
    tp.avg_score as temporal_avg_score,
    tp.score_stddev,
    tp.q1_score,
    tp.q3_score,
    tp.acceptance_rate,
    LAG(tp.post_count, 1) OVER (ORDER BY tp.week, tp.day_of_week, tp.hour_of_day) as prev_period_count,
    LEAD(tp.post_count, 1) OVER (ORDER BY tp.week, tp.day_of_week, tp.hour_of_day) as next_period_count,
    ROW_NUMBER() OVER (PARTITION BY th.TagName ORDER BY ue.Reputation DESC, ue.high_quality_answers DESC) as contributor_rank,
    CASE 
        WHEN pqm.score_percentile >= 90 THEN 'Elite'
        WHEN pqm.score_percentile >= 75 THEN 'High'
        WHEN pqm.score_percentile >= 50 THEN 'Medium'
        ELSE 'Standard'
    END as quality_tier
FROM tag_hierarchy th
CROSS JOIN LATERAL (
    SELECT * FROM user_expertise 
    ORDER BY high_quality_answers DESC, median_answer_score DESC 
    LIMIT 5
) ue
CROSS JOIN LATERAL (
    SELECT * FROM post_quality_metrics 
    WHERE score_percentile > 80
    ORDER BY Score DESC, ViewCount DESC 
    LIMIT 10
) pqm
CROSS JOIN LATERAL (
    SELECT * FROM temporal_patterns 
    ORDER BY post_count DESC, avg_score DESC 
    LIMIT 20
) tp
WHERE th.question_count > 100
ORDER BY 
    th.total_views DESC,
    ue.Reputation DESC,
    pqm.Score DESC,
    tp.acceptance_rate DESC
LIMIT 100;
