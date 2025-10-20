-- {"query": "68.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 122} 
WITH ranked_users AS (
  SELECT Id, DisplayName, Reputation,
         ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS user_rank
  FROM Users
),
top_users AS (
  SELECT Id, DisplayName, Reputation
  FROM ranked_users
  WHERE user_rank <= 10
)
SELECT tu.DisplayName, tu.Reputation, COUNT(DISTINCT p.Id) AS total_posts
FROM top_users tu
LEFT JOIN Posts p ON p.OwnerUserId = tu.Id
WHERE p.PostTypeId = 1
GROUP BY tu.Id, tu.DisplayName, tu.Reputation
ORDER BY tu.Reputation DESC;