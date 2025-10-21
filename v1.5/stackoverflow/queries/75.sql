-- {"query": "75.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 151} 
WITH ranked_users AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
    FROM Users u
),
top_users AS (
    SELECT ru.Id, ru.DisplayName, ru.Reputation
    FROM ranked_users ru
    WHERE ru.rn <= 100
)
SELECT tu.DisplayName, COUNT(DISTINCT p.Id) AS num_posts, SUM(v.BountyAmount) AS total_bounties
FROM top_users tu
LEFT JOIN Posts p ON tu.Id = p.OwnerUserId
LEFT JOIN Votes v ON p.Id = v.PostId
WHERE p.PostTypeId = 1
GROUP BY tu.Id, tu.DisplayName
ORDER BY total_bounties DESC;