-- {"query": "77.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 98} 
WITH RankedUsers AS (
    SELECT Id, DisplayName, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS Rank
    FROM Users
),
TopUsers AS (
    SELECT *
    FROM RankedUsers
    WHERE Rank <= 10
)
SELECT u.Id, u.DisplayName, COUNT(DISTINCT p.Id) AS TotalPosts
FROM TopUsers u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
GROUP BY u.Id, u.DisplayName
ORDER BY TotalPosts DESC;