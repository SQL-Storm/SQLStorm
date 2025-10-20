-- {"query": "15015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 37360, "output_tokens": 10991} 
WITH UserReputationStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        ROW_NUMBER() OVER (PARTITION BY 
            EXTRACT(YEAR FROM u.CreationDate) 
            ORDER BY u.Reputation DESC) AS YearlyReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostTagAnalysis AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostsWithTag,
        AVG(p.Score) AS AvgTagPostScore,
        MAX(p.ViewCount) AS MaxTagViewCount,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianTagPostScore
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
)
SELECT 
    u.DisplayName,
    u.Reputation,
    u.PostCount,
    u.AvgPostScore,
    u.BadgeCount,
    u.ReputationRank,
    t.TagName AS MostFrequentTag,
    t.PostsWithTag,
    t.AvgTagPostScore,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.UserId = u.UserId 
       AND v.VoteTypeId IN (2, 3)
    ) AS TotalVotes,
    CASE 
        WHEN u.Reputation > 10000 THEN 'High Rep'
        WHEN u.Reputation > 1000 THEN 'Medium Rep'
        ELSE 'Low Rep'
    END AS RepCategory
FROM UserReputationStats u
CROSS JOIN PostTagAnalysis t
WHERE u.AvgPostScore > (
    SELECT AVG(Score) 
    FROM Posts 
    WHERE PostTypeId = 1
)
AND t.PostsWithTag > 100
AND u.YearlyReputationRank <= 10
ORDER BY u.Reputation DESC, u.PostCount DESC
LIMIT 50;