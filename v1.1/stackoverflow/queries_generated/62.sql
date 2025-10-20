-- {"query": "62.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 141} 

WITH UserPostCounts AS (
    SELECT u.Id AS UserId, COUNT(DISTINCT p.Id) AS PostCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 10000
    GROUP BY u.Id
),
TopUsers AS (
    SELECT UserId, PostCount, RANK() OVER (ORDER BY PostCount DESC) AS Rank
    FROM UserPostCounts
)
SELECT u.Id, u.DisplayName, u.Location, tp.Rank
FROM Users u
JOIN TopUsers tp ON u.Id = tp.UserId
WHERE u.Location IS NOT NULL
ORDER BY tp.Rank
LIMIT 10;
