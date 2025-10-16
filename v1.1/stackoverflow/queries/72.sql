-- {"query": "72.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 244} 
WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation,
           ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS user_rank
    FROM Users
),
post_votes AS (
    SELECT p.Id AS post_id, COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS upvotes,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS downvotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id
),
top_users AS (
    SELECT ru.Id, ru.DisplayName, ru.Reputation, ru.user_rank, COALESCE(pv.upvotes, 0) AS total_upvotes,
           COALESCE(pv.downvotes, 0) AS total_downvotes
    FROM ranked_users ru
    LEFT JOIN post_votes pv ON ru.Id = pv.post_id
    WHERE ru.user_rank <= 10
)
SELECT tu.Id, tu.DisplayName, tu.Reputation, tu.user_rank, tu.total_upvotes, tu.total_downvotes
FROM top_users tu;