-- {"query": "2.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 129} 
WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation, 
           ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS user_rank
    FROM Users
),
top_users AS (
    SELECT Id, DisplayName, Reputation
    FROM ranked_users
    WHERE user_rank <= 100
)
SELECT u.DisplayName AS top_user_displayname, 
       u.Reputation AS top_user_reputation,
       COUNT(p.Id) AS total_posts
FROM top_users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1
GROUP BY u.DisplayName, u.Reputation
ORDER BY total_posts DESC;