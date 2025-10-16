-- {"query": "99.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 137} 
WITH ranked_users AS (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS user_rank
    FROM Users
),
top_users AS (
    SELECT *
    FROM ranked_users
    WHERE user_rank <= 100  -- Top 100 users based on Reputation
)
SELECT tu.DisplayName,
       COUNT(DISTINCT p.Id) AS num_posts,
       SUM(v.VoteTypeId) AS total_votes
FROM top_users tu
JOIN Posts p ON tu.Id = p.OwnerUserId
LEFT JOIN Votes v ON p.Id = v.PostId
GROUP BY tu.DisplayName
HAVING COUNT(DISTINCT p.Id) > 10
ORDER BY total_votes DESC;