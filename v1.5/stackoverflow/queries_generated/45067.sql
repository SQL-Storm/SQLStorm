-- {"query": "45067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 304}
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        AVG(p.Score) AS AvgPostScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostCountRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE p.PostTypeId = 1 AND u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
)
SELECT 
    UserId, 
    DisplayName, 
    TotalPosts, 
    AvgPostScore, 
    BadgeCount, 
    VoteCount,
    PostCountRank
FROM UserPostStats
WHERE BadgeCount > 5 AND AvgPostScore > 3
ORDER BY TotalPosts DESC, AvgPostScore DESC
LIMIT 100;
