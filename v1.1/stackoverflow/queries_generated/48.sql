-- {"query": "48.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 207} 
WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation, RANK() OVER(ORDER BY Reputation DESC) AS reputation_rank
    FROM Users
    WHERE Location IS NOT NULL
),
top_users AS (
    SELECT Id, DisplayName, Reputation, Location
    FROM ranked_users
    WHERE reputation_rank <= 10
),
user_badges AS (
    SELECT u.Id, u.DisplayName, b.Name AS BadgeName
    FROM top_users u
    INNER JOIN Badges b ON u.Id = b.UserId
),
user_post_counts AS (
    SELECT u.Id, u.DisplayName, COUNT(p.Id) AS TotalPosts
    FROM top_users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName
)
SELECT ub.Id AS UserId, ub.DisplayName AS UserName, ub.BadgeName, upc.TotalPosts
FROM user_badges ub
LEFT JOIN user_post_counts upc ON ub.Id = upc.Id;