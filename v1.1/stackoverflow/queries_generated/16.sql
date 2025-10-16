-- {"query": "16.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 157} 
WITH cte_users_reputation_rank AS (
    SELECT Id, Reputation, dense_rank() OVER (ORDER BY Reputation DESC) AS ReputationRank
    FROM Users
),
cte_top_users_posts_count AS (
    SELECT u.Id, u.DisplayName, COUNT(p.Id) AS TotalPosts
    FROM cte_users_reputation_rank u 
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName
    ORDER BY TotalPosts DESC
    LIMIT 10
)
SELECT tu.DisplayName, tu.TotalPosts, ru.ReputationRank
FROM cte_top_users_posts_count tu
INNER JOIN cte_users_reputation_rank ru ON tu.Id = ru.Id
ORDER BY ru.ReputationRank;