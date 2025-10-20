-- {"query": "45055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 126170, "output_tokens": 22619} 
WITH TopContributors AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AveragePostScore
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 50
), 
TagScores AS (
    SELECT 
        t.TagName,
        AVG(p.Score) AS AverageTagScore,
        COUNT(p.Id) AS TagPostCount
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 100
)
SELECT 
    tc.DisplayName,
    tc.PostCount,
    tc.TotalScore,
    tc.AveragePostScore,
    ts.TagName,
    ts.AverageTagScore,
    ts.TagPostCount
FROM TopContributors tc
CROSS JOIN TagScores ts
WHERE tc.AveragePostScore > ts.AverageTagScore
ORDER BY tc.PostCount DESC, ts.TagPostCount DESC
LIMIT 100;