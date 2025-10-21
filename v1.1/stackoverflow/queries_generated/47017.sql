-- {"query": "47017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 2026}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) as direct_posts,
        1 as level
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    JOIN Posts pt ON pt.Id = p.Id
    WHERE t.Count > 1000
    GROUP BY t.Id, t.TagName
    
    UNION ALL
    
    SELECT 
        t.Id,
        t.TagName,
        th.direct_posts,
        th.level + 1
    FROM Tags t
    JOIN tag_hierarchy th ON th.Id != t.Id
    WHERE th.level < 3
),
user_expertise AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        string_agg(DISTINCT substring(p.Tags, 2, position('>' IN substring(p.Tags, 2)) - 1), ', ') as primary_tags,
        COUNT(DISTINCT p.Id) as total_posts,
        SUM(p.Score) as total_score,
        AVG(p.Score)::numeric(10,2) as avg_score,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers,
        COUNT(DISTINCT b.Id) as badge_count,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as gold_badges,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score,
        STDDEV(p.Score)::numeric(10,2) as score_stddev
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 5000
        AND p.Score > 0
        AND p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 50
),
post_evolution AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COUNT(DISTINCT ph.Id) as edit_count,
        MAX(ph.CreationDate) - MIN(ph.CreationDate) as edit_timespan,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN ph.Id END) as close_reopen_cycles,
        COUNT(DISTINCT c.Id) as comment_count,
        AVG(c.Score) as avg_comment_score,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as upvotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as downvotes,
        CASE 
            WHEN p.ViewCount > 0 THEN p.Score::numeric / p.ViewCount * 100 
            ELSE 0 
        END as score_per_view_pct,
        RANK() OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate) ORDER BY p.Score DESC) as monthly_rank
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
        AND p.Score > 10
        AND p.ViewCount > 1000
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount
),
answer_quality AS (
    SELECT 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        q.Score as QuestionScore,
        a.CreationDate - q.CreationDate as time_to_answer,
        CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END as is_accepted,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) as answer_rank,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate) as answer_order,
        LENGTH(a.Body) as answer_length,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = a.Id) as links_count
    FROM Posts a
    JOIN Posts q ON q.Id = a.ParentId
    WHERE a.PostTypeId = 2
        AND q.PostTypeId = 1
        AND a.Score > 0
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    ue.total_posts,
    ue.total_score,
    ue.avg_score,
    ue.median_score,
    ue.score_stddev,
    ue.questions,
    ue.answers,
    ue.gold_badges,
    ue.badge_count,
    pe.Title as top_question,
    pe.Score as top_question_score,
    pe.ViewCount as top_question_views,
    pe.edit_count,
    pe.close_reopen_cycles,
    pe.score_per_view_pct,
    pe.monthly_rank,
    COUNT(DISTINCT aq.AnswerId) as quality_answers,
    AVG(aq.time_to_answer) as avg_response_time,
    SUM(aq.is_accepted) as accepted_answers,
    AVG(aq.answer_length)::numeric(10,0) as avg_answer_length,
    STRING_AGG(DISTINCT th.TagName, ', ' ORDER BY th.TagName) as related_tags,
    MAX(th.direct_posts) as max_tag_posts,
    COALESCE(ue.primary_tags, '') as primary_expertise,
    DENSE_RANK() OVER (ORDER BY ue.total_score DESC) as global_score_rank,
    DENSE_RANK() OVER (ORDER BY ue.avg_score DESC) as global_avg_rank,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY pe.ViewCount) OVER (PARTITION BY ue.UserId) as view_75th_percentile
FROM user_expertise ue
CROSS JOIN LATERAL (
    SELECT * FROM post_evolution pe2
    WHERE pe2.Id IN (SELECT Id FROM Posts WHERE OwnerUserId = ue.UserId)
    ORDER BY pe2.Score DESC
    LIMIT 1
) pe
LEFT JOIN answer_quality aq ON aq.AnswerId IN (SELECT Id FROM Posts WHERE OwnerUserId = ue.UserId AND PostTypeId = 2)
LEFT JOIN tag_hierarchy th ON th.TagName IN (SELECT unnest(string_to_array(ue.primary_tags, ', ')))
WHERE ue.total_score > 100
GROUP BY 
    ue.UserId, ue.DisplayName, ue.Reputation, ue.total_posts, ue.total_score, 
    ue.avg_score, ue.median_score, ue.score_stddev, ue.questions, ue.answers,
    ue.gold_badges, ue.badge_count, pe.Title, pe.Score, pe.ViewCount, pe.edit_count,
    pe.close_reopen_cycles, pe.score_per_view_pct, pe.monthly_rank, ue.primary_tags
HAVING COUNT(DISTINCT aq.AnswerId) > 5
ORDER BY ue.total_score DESC, global_avg_rank
LIMIT 100;
