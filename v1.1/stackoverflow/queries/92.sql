-- {"query": "92.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 168} 
WITH ranked_users AS (
    SELECT Id, Reputation, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
),
ranked_posts AS (
    SELECT p.Id, p.OwnerUserId, p.Score, ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rank
    FROM Posts p
),
top_users_and_posts AS (
    SELECT u.Id AS user_id, u.Reputation, u.rank AS user_rank, p.Id AS post_id, p.Score, p.rank AS post_rank
    FROM ranked_users u
    JOIN ranked_posts p ON u.Id = p.OwnerUserId AND p.rank <= 5
)
SELECT tu.user_id, tu.Reputation, tu.user_rank, tu.post_id, tu.Score, tu.post_rank
FROM top_users_and_posts tu;