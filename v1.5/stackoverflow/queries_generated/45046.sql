-- {"query": "45046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 105524, "output_tokens": 18716} 
WITH HotTopUsers AS (
    SELECT u.Id, u.Reputation, u.DisplayName, 
           COUNT(DISTINCT p.Id) AS PostCount, 
           AVG(p.Score) AS AvgPostScore,
           SUM(v.BountyAmount) AS TotalBounties
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.Reputation, u.DisplayName
),
TagPopularity AS (
    SELECT t.TagName, 
           COUNT(DISTINCT p.Id) AS PostCount, 
           AVG(p.Score) AS AvgTagScore,
           MAX(p.ViewCount) AS MaxTagViewCount
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName
)
SELECT 
    hu.DisplayName,
    hu.Reputation,
    hu.PostCount,
    hu.AvgPostScore,
    hu.TotalBounties,
    tp.TagName,
    tp.PostCount AS TagPostCount,
    tp.AvgTagScore,
    tp.MaxTagViewCount
FROM HotTopUsers hu
CROSS JOIN TagPopularity tp
WHERE hu.AvgPostScore > 10 AND tp.PostCount > 100
ORDER BY hu.Reputation DESC, tp.PostCount DESC
LIMIT 500;