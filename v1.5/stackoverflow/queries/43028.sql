-- {"query": "43028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 504} 
WITH UserActivity AS (
    SELECT 
        OwnerUserId,
        COUNT(Id) AS TotalPosts,
        SUM(Score) AS TotalScore,
        AVG(Score) AS AvgScore,
        MAX(LastEditDate) AS LatestActivityDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
TopContributors AS (
    SELECT 
        u.DisplayName,
        u.Reputation,
        ua.TotalPosts,
        ua.TotalScore,
        ua.AvgScore,
        ua.LatestActivityDate,
        b.BadgeCount
    FROM Users u
    JOIN UserActivity ua ON u.Id = ua.OwnerUserId
    LEFT JOIN (
        SELECT 
            UserId, 
            COUNT(*) AS BadgeCount 
        FROM Badges 
        GROUP BY UserId
    ) b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    ORDER BY u.Reputation DESC, ua.TotalPosts DESC
    LIMIT 100
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.ViewCount) AS MaxPostViews
    FROM Tags t
    JOIN Posts p ON ',' || p.Tags || ',' LIKE '%,' || t.TagName || ',%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 10
    ORDER BY PostCount DESC
    LIMIT 50
)
SELECT 
    tc.DisplayName,
    tc.Reputation,
    tc.TotalPosts,
    tc.TotalScore,
    tc.AvgScore,
    tc.LatestActivityDate,
    tc.BadgeCount,
    ta.TagName,
    ta.PostCount,
    ta.AvgPostScore,
    ta.MaxPostViews
FROM TopContributors tc
CROSS JOIN TagAnalysis ta
ORDER BY tc.Reputation DESC, ta.PostCount DESC;