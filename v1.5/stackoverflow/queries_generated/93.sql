-- {"query": "93.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 117} 
WITH ranked_users AS (
    SELECT 
        Id,
        Reputation,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
),
top_10_users AS (
    SELECT 
        Id,
        Reputation,
        rank
    FROM ranked_users
    WHERE rank <= 10
)
SELECT 
    c.UserId,
    u.DisplayName,
    u.Location,
    c.Score,
    c.Text
FROM Comments c
JOIN top_10_users u ON c.UserId = u.Id
WHERE c.Score > 5
ORDER BY u.Reputation DESC;