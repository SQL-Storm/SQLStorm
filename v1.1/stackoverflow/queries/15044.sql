-- {"query": "15044.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 105075, "output_tokens": 31148} 
WITH UserReputationStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianPostScore,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS YearlyReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count,
        CASE 
            WHEN t.Count > 10000 THEN 'Extremely Popular'
            WHEN t.Count > 5000 THEN 'Very Popular'
            WHEN t.Count > 1000 THEN 'Popular'
            ELSE 'Niche'
        END AS PopularityCategory,
        AVG(p.Score) AS AveragePostScore
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName, t.Count
)
SELECT 
    urs.UserId,
    urs.DisplayName,
    urs.Reputation,
    urs.TotalPosts,
    urs.TotalVotes,
    urs.MedianPostScore,
    urs.ReputationRank,
    tp.TagName,
    tp.PopularityCategory,
    tp.AveragePostScore,
    CASE 
        WHEN urs.Reputation > 10000 AND urs.TotalPosts > 50 THEN 'Elite User'
        WHEN urs.Reputation > 5000 AND urs.TotalPosts > 20 THEN 'Established User'
        ELSE 'Regular User'
    END AS UserCategory,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = urs.UserId) AS TotalBadges
FROM UserReputationStats urs
CROSS JOIN LATERAL (
    SELECT TagName, PopularityCategory, AveragePostScore
    FROM TagPopularity
    ORDER BY ABS(RANDOM()) 
    LIMIT 1
) tp
WHERE urs.TotalPosts > 0
    AND (urs.Reputation > 1000 OR urs.TotalVotes > 100)
ORDER BY urs.Reputation DESC, urs.TotalPosts DESC
LIMIT 100;