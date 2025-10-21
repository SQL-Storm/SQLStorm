-- {"query": "51.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 99} 
WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation,
           ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
),
top_users AS (
    SELECT *
    FROM ranked_users
    WHERE rank <= 10
)
SELECT tu.DisplayName, tu.Reputation, COUNT(v.Id) AS TotalVotes
FROM top_users tu
LEFT JOIN Votes v ON tu.Id = v.UserId
GROUP BY tu.DisplayName, tu.Reputation
ORDER BY TotalVotes DESC;