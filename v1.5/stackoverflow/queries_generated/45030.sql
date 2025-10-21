-- {"query": "45030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 523}
WITH UserReputationAnalysis AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        AVG(p.Score) AS AveragePostScore,
        MAX(p.CreationDate) AS LastPostDate,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagPopularity AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostsWithTag,
        AVG(p.Score) AS AverageTagScore,
        COUNT(DISTINCT pl.Id) AS RelatedPostLinks
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
    GROUP BY t.TagName
)
SELECT 
    ura.UserId,
    ura.DisplayName,
    ura.Reputation,
    ura.PostCount,
    ura.VoteCount,
    ura.BadgeCount,
    ura.AveragePostScore,
    tp.TagName AS MostFrequentTag,
    tp.PostsWithTag AS TagFrequency,
    tp.AverageTagScore
FROM UserReputationAnalysis ura
JOIN TagPopularity tp ON tp.PostsWithTag = (
    SELECT MAX(PostsWithTag)
    FROM TagPopularity
)
ORDER BY ura.Reputation DESC, ura.PostCount DESC
LIMIT 100;
