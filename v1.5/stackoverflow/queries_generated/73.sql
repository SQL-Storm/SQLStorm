-- {"query": "73.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 120} 
WITH ranked_users AS (
    SELECT u.Id, u.DisplayName, u.Reputation, 
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
    FROM Users u
),
top_users AS (
    SELECT Id, DisplayName, Reputation
    FROM ranked_users
    WHERE rn <= 100
)
SELECT tu.Id AS user_id, tu.DisplayName AS user_name, SUM(v.BountyAmount) AS total_bounty
FROM top_users tu
LEFT JOIN Votes v ON tu.Id = v.UserId
GROUP BY tu.Id, tu.DisplayName
ORDER BY total_bounty DESC;