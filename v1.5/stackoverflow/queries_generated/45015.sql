-- {"query": "45015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 390}
WITH UserPostActivity AS (
    SELECT 
        u.Id AS UserId, 
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation
),
TagPopularity AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS TagPostCount,
        AVG(p.Score) AS AvgTagScore,
        MAX(p.ViewCount) AS MaxViewCount
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName
)
SELECT 
    upa.UserId,
    upa.Reputation,
    upa.PostCount,
    upa.VoteCount,
    upa.AvgPostScore,
    tp.TagName,
    tp.TagPostCount,
    tp.AvgTagScore
FROM UserPostActivity upa
CROSS JOIN TagPopularity tp
WHERE 
    upa.PostCount > 10 
    AND tp.TagPostCount > 100
ORDER BY 
    upa.Reputation DESC, 
    tp.TagPostCount DESC
LIMIT 1000;
