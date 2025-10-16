-- {"query": "32.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 118} 
WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rnk
    FROM Users
), top_users AS (
    SELECT Id, DisplayName, Reputation
    FROM ranked_users
    WHERE rnk <= 100
)
SELECT tu.DisplayName, tu.Reputation, COUNT(Posts.Id) AS TotalPosts
FROM top_users tu
LEFT JOIN Posts ON tu.Id = Posts.OwnerUserId
WHERE Posts.PostTypeId = 1
GROUP BY tu.Id, tu.DisplayName, tu.Reputation
ORDER BY tu.Reputation DESC;