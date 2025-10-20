-- {"query": "86.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 197} 
WITH ranked_users AS (
    SELECT Id, Reputation, ROW_NUMBER() OVER(ORDER BY Reputation DESC) AS rank
    FROM Users
),
top_users AS (
    SELECT Id, Reputation, rank
    FROM ranked_users
    WHERE rank <= 100
),
user_badges AS (
    SELECT u.Id AS UserId, u.Reputation, b.Name AS BadgeName
    FROM top_users u 
    JOIN Badges b ON u.Id = b.UserId
),
user_post_counts AS (
    SELECT u.Id AS UserId, COUNT(DISTINCT p.Id) AS NumPosts
    FROM top_users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY u.Id
)
SELECT ub.UserId, ub.Reputation, ub.BadgeName, upc.NumPosts
FROM user_badges ub
JOIN user_post_counts upc ON ub.UserId = upc.UserId
ORDER BY ub.Reputation DESC;