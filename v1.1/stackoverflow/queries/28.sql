-- {"query": "28.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 121} 
WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation,
           ROW_NUMBER() OVER(ORDER BY Reputation DESC) AS rank
    FROM Users
),
top_users AS (
    SELECT Id, DisplayName, Reputation
    FROM ranked_users
    WHERE rank <= 10
)
SELECT top_users.DisplayName, top_users.Reputation, COUNT(Posts.Id) AS NumPosts
FROM top_users
LEFT JOIN Posts ON top_users.Id = Posts.OwnerUserId
WHERE Posts.PostTypeId = 1
GROUP BY top_users.Id, top_users.DisplayName, top_users.Reputation
ORDER BY NumPosts DESC;