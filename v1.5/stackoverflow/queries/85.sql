-- {"query": "85.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 127} 
WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
),
top_users AS (
    SELECT *
    FROM ranked_users
    WHERE rank <= 100
)
SELECT tu.DisplayName, tu.Reputation, p.Title, p.CreationDate, COUNT(c.Id) AS CommentCount
FROM top_users tu
JOIN Posts p ON tu.Id = p.OwnerUserId
LEFT JOIN Comments c ON p.Id = c.PostId
GROUP BY tu.DisplayName, tu.Reputation, p.Title, p.CreationDate
ORDER BY tu.Reputation DESC;