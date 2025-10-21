-- {"query": "87.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 167} 
WITH ranked_users AS (
    SELECT Id, Reputation, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
),
high_reputation_users AS (
    SELECT Id, Reputation
    FROM ranked_users
    WHERE rank <= 100
),
top_user_post_counts AS (
    SELECT u.Id, u.Reputation, COUNT(p.Id) AS post_count
    FROM high_reputation_users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.Reputation
)
SELECT u.Id, u.Reputation, u.CreationDate, u.DisplayName, t.post_count
FROM Users u
JOIN top_user_post_counts t ON u.Id = t.Id
ORDER BY t.post_count DESC, u.Reputation DESC;