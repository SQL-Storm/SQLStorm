-- {"query": "45068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 425}
WITH TagPopularity AS (
    SELECT t.TagName, 
           AVG(p.Score) AS avg_tag_score, 
           COUNT(DISTINCT p.Id) AS total_posts,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) AS median_view_count
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
UserActivityProfile AS (
    SELECT 
        u.Id,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS questions_asked,
        COUNT(DISTINCT v.Id) AS total_votes_cast,
        COUNT(DISTINCT b.Id) AS badge_count,
        AVG(p.Score) AS avg_question_score
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.Reputation
)
SELECT 
    tp.TagName,
    tp.avg_tag_score,
    tp.total_posts,
    tp.median_view_count,
    uap.Reputation,
    uap.questions_asked,
    uap.total_votes_cast,
    uap.badge_count,
    uap.avg_question_score
FROM TagPopularity tp
JOIN UserActivityProfile uap ON uap.questions_asked > 10
WHERE tp.total_posts > 100
ORDER BY tp.avg_tag_score DESC, uap.Reputation DESC
LIMIT 500;
