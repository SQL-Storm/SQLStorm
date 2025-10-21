-- {"query": "47077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1940}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) as direct_questions,
        ARRAY[t.TagName] as tag_path,
        1 as depth
    FROM Tags t
    INNER JOIN Posts pt ON pt.Tags LIKE '%<' || t.TagName || '>%'
    WHERE pt.PostTypeId = 1
        AND t.Count > 1000
    GROUP BY t.Id, t.TagName
    
    UNION ALL
    
    SELECT 
        t2.Id,
        t2.TagName,
        th.direct_questions,
        th.tag_path || t2.TagName,
        th.depth + 1
    FROM tag_hierarchy th
    CROSS JOIN Tags t2
    WHERE th.depth < 3
        AND t2.Id != ALL(SELECT t3.Id FROM Tags t3 WHERE t3.TagName = ANY(th.tag_path))
        AND EXISTS (
            SELECT 1 FROM Posts p 
            WHERE p.Tags LIKE '%<' || th.tag_path[1] || '>%'
                AND p.Tags LIKE '%<' || t2.TagName || '>%'
                AND p.PostTypeId = 1
        )
),
user_expertise AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        t.TagName,
        COUNT(DISTINCT p.Id) as answers_in_tag,
        SUM(p.Score) as total_score_in_tag,
        AVG(p.Score) as avg_score_in_tag,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score_in_tag,
        COUNT(DISTINCT CASE WHEN p.Id = q.AcceptedAnswerId THEN p.Id END) as accepted_answers,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.TagBased = B'1' AND b.Name = t.TagName) as tag_badges,
        DENSE_RANK() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) as rank_in_tag
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
    INNER JOIN Posts q ON p.ParentId = q.Id AND q.PostTypeId = 1
    INNER JOIN Tags t ON q.Tags LIKE '%<' || t.TagName || '>%'
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 5000
        AND p.Score > 0
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
question_quality AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score as question_score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        EXTRACT(EPOCH FROM (COALESCE(p.ClosedDate, CURRENT_TIMESTAMP) - p.CreationDate)) / 3600 as hours_until_closed,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) as edit_count,
        COUNT(DISTINCT c.Id) as comment_count,
        AVG(a.Score) FILTER (WHERE a.PostTypeId = 2) as avg_answer_score,
        MAX(a.Score) FILTER (WHERE a.PostTypeId = 2) as best_answer_score,
        STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.Count DESC) as all_tags,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_question_score,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as next_question_score
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Tags t ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
        AND p.Score >= 5
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, 
             p.FavoriteCount, p.ClosedDate, p.CreationDate, p.OwnerUserId
)
SELECT 
    ue.DisplayName,
    ue.TagName,
    ue.answers_in_tag,
    ue.total_score_in_tag,
    ue.avg_score_in_tag,
    ue.median_score_in_tag,
    ue.accepted_answers,
    ue.tag_badges,
    ue.rank_in_tag,
    COUNT(DISTINCT qq.QuestionId) as high_quality_questions_answered,
    AVG(qq.question_score) as avg_question_quality,
    AVG(qq.ViewCount) as avg_question_views,
    AVG(qq.hours_until_closed) FILTER (WHERE qq.hours_until_closed IS NOT NULL) as avg_hours_until_closed,
    CORR(qq.question_score, qq.best_answer_score) as score_correlation,
    STRING_AGG(DISTINCT th.TagName, ', ' ORDER BY th.direct_questions DESC) FILTER (WHERE th.depth = 2) as related_tags,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY qq.ViewCount) as p90_views,
    STDDEV(qq.question_score) as question_score_stddev,
    COUNT(DISTINCT DATE_TRUNC('week', p2.CreationDate)) as active_weeks,
    JSON_AGG(
        JSON_BUILD_OBJECT(
            'question_title', qq.Title,
            'score', qq.question_score,
            'views', qq.ViewCount
        ) ORDER BY qq.question_score DESC
    ) FILTER (WHERE ROW_NUMBER() OVER (PARTITION BY ue.UserId, ue.TagName ORDER BY qq.question_score DESC) <= 3) as top_questions
FROM user_expertise ue
LEFT JOIN Posts p2 ON p2.OwnerUserId = ue.UserId 
    AND p2.PostTypeId = 2
LEFT JOIN Posts q2 ON p2.ParentId = q2.Id 
    AND q2.Tags LIKE '%<' || ue.TagName || '>%'
LEFT JOIN question_quality qq ON qq.QuestionId = q2.Id
LEFT JOIN tag_hierarchy th ON th.tag_path[1] = ue.TagName
WHERE ue.rank_in_tag <= 100
GROUP BY ue.UserId, ue.DisplayName, ue.TagName, ue.answers_in_tag, 
         ue.total_score_in_tag, ue.avg_score_in_tag, ue.median_score_in_tag,
         ue.accepted_answers, ue.tag_badges, ue.rank_in_tag
HAVING COUNT(DISTINCT qq.QuestionId) > 0
ORDER BY ue.total_score_in_tag DESC, ue.avg_score_in_tag DESC
LIMIT 500;
