-- {"query": "45093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 374}
WITH TagPopularity AS (
    SELECT 
        t.TagName, 
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.ViewCount) AS MaxViews
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
UserActivity AS (
    SELECT 
        u.Id, 
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostsCreated,
        COUNT(DISTINCT v.Id) AS VotesGiven,
        COUNT(DISTINCT b.Id) AS BadgesEarned
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.Reputation
)
SELECT 
    tp.TagName,
    tp.PostCount,
    tp.AvgScore,
    tp.MaxViews,
    ua.Reputation,
    ua.PostsCreated,
    ua.VotesGiven,
    ua.BadgesEarned
FROM TagPopularity tp
JOIN UserActivity ua ON ua.PostsCreated > 10
WHERE tp.PostCount > 100
ORDER BY tp.AvgScore DESC, tp.PostCount DESC
LIMIT 50;
