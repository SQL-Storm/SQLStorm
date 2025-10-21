-- {"query": "47033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 2051}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.PostId) as post_count,
        1 as level
    FROM Tags t
    JOIN (
        SELECT p.Id as PostId, unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag
        FROM Posts p
        WHERE p.PostTypeId = 1
    ) pt ON pt.tag = t.TagName
    WHERE t.Count > 1000
    GROUP BY t.Id, t.TagName
),
user_expertise AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        pt.tag,
        COUNT(DISTINCT p.Id) as answer_count,
        SUM(p.Score) as total_score,
        AVG(p.Score) as avg_score,
        MAX(p.Score) as max_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score,
        COUNT(DISTINCT CASE WHEN p.Id = q.AcceptedAnswerId THEN p.Id END) as accepted_answers,
        AVG(EXTRACT(EPOCH FROM (p.CreationDate - q.CreationDate))/3600) as avg_response_time_hours,
        COUNT(DISTINCT b.Name) FILTER (WHERE b.TagBased = '1' AND b.Name = pt.tag) as tag_badges
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
    JOIN Posts q ON q.Id = p.ParentId
    JOIN LATERAL (
        SELECT unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as tag
    ) pt ON true
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 5000
        AND p.Score > 0
        AND q.CreationDate >= NOW() - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, pt.tag
    HAVING COUNT(DISTINCT p.Id) >= 10
),
question_quality AS (
    SELECT 
        q.Id as QuestionId,
        q.Title,
        q.Score as question_score,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.CreationDate,
        q.OwnerUserId,
        CASE 
            WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN q.AnswerCount > 0 THEN 'HasAnswers'
            ELSE 'Unanswered'
        END as status,
        COUNT(DISTINCT ph.Id) as edit_count,
        COUNT(DISTINCT c.Id) as comment_count,
        AVG(a.Score) as avg_answer_score,
        MAX(a.Score) as best_answer_score,
        MIN(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600) as time_to_first_answer_hours,
        COUNT(DISTINCT pl.Id) FILTER (WHERE pl.LinkTypeId = 3) as duplicate_links,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as upvotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as downvotes
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN PostHistory ph ON ph.PostId = q.Id AND ph.PostHistoryTypeId IN (4,5,6)
    LEFT JOIN Comments c ON c.PostId = q.Id
    LEFT JOIN PostLinks pl ON pl.PostId = q.Id
    LEFT JOIN Votes v ON v.PostId = q.Id
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= NOW() - INTERVAL '1 year'
        AND q.Score >= 5
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount, 
             q.CreationDate, q.OwnerUserId, q.ClosedDate, q.AcceptedAnswerId
),
user_activity_patterns AS (
    SELECT 
        u.Id,
        u.DisplayName,
        EXTRACT(DOW FROM p.CreationDate) as day_of_week,
        EXTRACT(HOUR FROM p.CreationDate) as hour_of_day,
        COUNT(DISTINCT p.Id) as post_count,
        AVG(p.Score) as avg_score,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as answers,
        STDDEV(p.Score) as score_variance
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= NOW() - INTERVAL '6 months'
        AND u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, EXTRACT(DOW FROM p.CreationDate), EXTRACT(HOUR FROM p.CreationDate)
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    ue.tag as expertise_tag,
    ue.answer_count,
    ue.total_score,
    ue.avg_score,
    ue.median_score,
    ue.accepted_answers,
    ROUND(ue.accepted_answers::numeric / NULLIF(ue.answer_count, 0) * 100, 2) as acceptance_rate,
    ue.avg_response_time_hours,
    ue.tag_badges,
    COUNT(DISTINCT qq.QuestionId) as high_quality_questions_answered,
    AVG(qq.question_score) as avg_question_score_answered,
    AVG(qq.ViewCount) as avg_views_of_answered_questions,
    SUM(qq.upvotes - qq.downvotes) as net_votes_on_answered_questions,
    MAX(uap.post_count) as peak_hour_posts,
    AVG(uap.score_variance) as consistency_score,
    DENSE_RANK() OVER (PARTITION BY ue.tag ORDER BY ue.total_score DESC) as tag_rank,
    DENSE_RANK() OVER (ORDER BY ue.Reputation DESC) as global_rank,
    LAG(ue.total_score, 1) OVER (PARTITION BY ue.tag ORDER BY ue.total_score DESC) - ue.total_score as score_gap_to_next,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY qq.time_to_first_answer_hours) 
        OVER (PARTITION BY ue.tag) as tag_75th_percentile_response_time
FROM user_expertise ue
LEFT JOIN question_quality qq ON qq.QuestionId IN (
    SELECT p.ParentId 
    FROM Posts p 
    WHERE p.OwnerUserId = ue.UserId 
        AND p.PostTypeId = 2
)
LEFT JOIN user_activity_patterns uap ON uap.Id = ue.UserId
WHERE ue.answer_count >= 20
    AND ue.avg_score > 5
GROUP BY 
    ue.DisplayName, ue.Reputation, ue.tag, ue.answer_count, 
    ue.total_score, ue.avg_score, ue.median_score, ue.accepted_answers,
    ue.avg_response_time_hours, ue.tag_badges, ue.UserId
ORDER BY ue.tag, ue.total_score DESC
LIMIT 1000;
