-- {"query": "60.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 125} 
WITH ranked_users AS (
    SELECT Id, Reputation, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
),
top_ten_percent AS (
    SELECT Id, Reputation, rank
    FROM ranked_users
    WHERE rank <= (SELECT COUNT(*) * 0.1 FROM Users)
)
SELECT u.Id, u.DisplayName, u.Reputation, b.Name AS BadgeName
FROM top_ten_percent ttp
JOIN Users u ON ttp.Id = u.Id
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE b.Class = 1
ORDER BY u.Reputation DESC;