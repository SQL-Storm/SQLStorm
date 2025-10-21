-- {"query": "45069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 402}
WITH UserPostInteractions AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(p.Score) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation
),
TagPopularity AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS PostsWithTag,
        AVG(p.ViewCount) AS AvgTagViewCount,
        MAX(p.Score) AS MaxTagScore
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName
)
SELECT 
    upi.UserId,
    upi.Reputation,
    upi.PostCount,
    upi.VoteCount,
    upi.CommentCount,
    upi.AvgPostScore,
    tp.TagName AS MostInterestingTag,
    tp.PostsWithTag,
    tp.AvgTagViewCount
FROM UserPostInteractions upi
JOIN TagPopularity tp ON tp.PostsWithTag > 100
ORDER BY upi.Reputation DESC, upi.PostCount DESC
LIMIT 500;
