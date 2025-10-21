-- {"query": "45073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 343}
WITH TagPopularity AS (
    SELECT 
        t.TagName, 
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AverageScore,
        MAX(p.ViewCount) as MaxViews
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
UserActivity AS (
    SELECT 
        u.Id, 
        u.DisplayName,
        COUNT(DISTINCT p.Id) as PostCount,
        SUM(p.Score) as TotalScore,
        COUNT(DISTINCT v.Id) as VoteCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 10
)
SELECT 
    tp.TagName,
    tp.QuestionCount,
    tp.AverageScore,
    ua.DisplayName,
    ua.PostCount,
    ua.TotalScore
FROM TagPopularity tp
JOIN UserActivity ua ON ua.TotalScore > tp.MaxViews
WHERE tp.QuestionCount > 100
ORDER BY tp.AverageScore DESC
LIMIT 50;
