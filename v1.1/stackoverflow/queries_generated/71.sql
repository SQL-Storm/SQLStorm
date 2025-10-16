-- {"query": "71.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 116} 
WITH ranked_users AS (
    SELECT Id, Reputation, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
),
top_users AS (
    SELECT Id, Reputation
    FROM ranked_users
    WHERE rank <= 100
)
SELECT u.Id, u.DisplayName, u.Reputation, COUNT(DISTINCT p.Id) AS num_posts
FROM top_users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
WHERE p.Score >= 10
GROUP BY u.Id, u.DisplayName, u.Reputation
ORDER BY num_posts DESC;