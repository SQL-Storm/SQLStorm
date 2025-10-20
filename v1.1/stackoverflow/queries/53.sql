-- {"query": "53.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 113} 
WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation,
           ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rn
    FROM Users
),
top_users AS (
    SELECT Id, DisplayName, Reputation
    FROM ranked_users
    WHERE rn <= 100
)
SELECT tu.DisplayName, tu.Reputation, COUNT(p.Id) AS TotalPosts
FROM top_users tu
LEFT JOIN Posts p ON tu.Id = p.OwnerUserId
WHERE p.PostTypeId = 1
GROUP BY tu.DisplayName, tu.Reputation
ORDER BY TotalPosts DESC;