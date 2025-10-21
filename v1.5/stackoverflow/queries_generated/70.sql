-- {"query": "70.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 245} 
WITH cte_post_scores AS (
    SELECT
        p.Id AS post_id,
        COALESCE(p.Score, 0) AS post_score,
        COUNT(v.Id) AS vote_count
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.Score
),

cte_max_score_per_user AS (
    SELECT
        u.Id AS user_id,
        MAX(p.post_score) AS max_post_score
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id
)

SELECT
    u.DisplayName,
    u.Reputation,
    MAX(ps.post_score) AS max_post_score,
    SUM(ps.vote_count) AS total_votes
FROM Users u
LEFT JOIN cte_max_score_per_user ms ON u.Id = ms.user_id
LEFT JOIN cte_post_scores ps ON u.Id = ps.post_id
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(ps.post_id) > 5
ORDER BY total_votes DESC, max_post_score DESC;