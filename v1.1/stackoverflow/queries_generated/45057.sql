-- {"query": "45057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 130758, "output_tokens": 23297} 
WITH TagPopularity AS (
    SELECT 
        t.TagName, 
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.ViewCount) AS MaxViewCount
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(p.Score) AS TotalPostScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.Reputation
)
SELECT 
    tp.TagName,
    tp.PostCount,
    tp.AvgScore,
    ua.Reputation,
    ua.TotalPosts,
    ua.BadgeCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId IN (SELECT Id FROM Posts WHERE Tags LIKE '%' || tp.TagName || '%')) AS RelatedPostLinksCount
FROM TagPopularity tp
JOIN UserActivity ua ON ua.TotalPostScore > tp.AvgScore * 10
WHERE tp.PostCount > 100
    AND ua.Reputation > 1000
ORDER BY tp.PostCount DESC, ua.Reputation DESC
LIMIT 50;