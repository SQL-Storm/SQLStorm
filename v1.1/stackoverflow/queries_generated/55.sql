-- {"query": "55.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 112} 
WITH RankedUsers AS (
    SELECT Id, Reputation, 
           ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS Rank
    FROM Users
),
TopUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM RankedUsers
    WHERE Rank <= 100
)
SELECT u.DisplayName, u.Reputation, COUNT(p.Id) AS TotalPosts
FROM TopUsers u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1
GROUP BY u.DisplayName, u.Reputation
ORDER BY TotalPosts DESC;