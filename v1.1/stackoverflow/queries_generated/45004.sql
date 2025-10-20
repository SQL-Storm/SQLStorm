-- {"query": "45004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 9176, "output_tokens": 1547} 
WITH UserTagInteractions AS (
    SELECT 
        p.OwnerUserId,
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalTagScore,
        MAX(p.ViewCount) AS MaxTagViewCount
    FROM Posts p
    CROSS JOIN (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName 
        FROM Posts p 
        WHERE p.Tags IS NOT NULL
    ) t
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, t.TagName
),
TagPerformanceRanking AS (
    SELECT 
        OwnerUserId,
        TagName,
        PostCount,
        TotalTagScore,
        MaxTagViewCount,
        DENSE_RANK() OVER (PARTITION BY OwnerUserId ORDER BY TotalTagScore DESC) AS TagScoreRank
    FROM UserTagInteractions
)
SELECT 
    u.Id AS UserId,
    u.Reputation,
    t.TagName,
    t.PostCount,
    t.TotalTagScore,
    t.MaxTagViewCount,
    t.TagScoreRank,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount
FROM Users u
JOIN TagPerformanceRanking t ON u.Id = t.OwnerUserId
WHERE t.TagScoreRank <= 3
ORDER BY t.TotalTagScore DESC, u.Reputation DESC
LIMIT 500;