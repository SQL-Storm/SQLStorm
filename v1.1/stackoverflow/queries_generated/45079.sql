-- {"query": "45079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 404}
WITH TopActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(p.Id) as PostCount,
        SUM(p.Score) as TotalScore,
        MAX(p.LastActivityDate) as LatestActivity,
        DENSE_RANK() OVER (ORDER BY COUNT(p.Id) DESC) as PostRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate > '2020-01-01'
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 10
),
TagInteractions AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) as PostsWithTag,
        AVG(p.Score) as AverageTagScore,
        COUNT(DISTINCT v.Id) as VoteCount
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
)
SELECT 
    tau.DisplayName,
    tau.PostCount,
    tau.TotalScore,
    tau.PostRank,
    ti.TagName,
    ti.PostsWithTag,
    ti.AverageTagScore
FROM TopActiveUsers tau
CROSS JOIN TagInteractions ti
WHERE tau.PostRank <= 50 AND ti.PostsWithTag > 100
ORDER BY tau.PostCount DESC, ti.AverageTagScore DESC
LIMIT 1000;
