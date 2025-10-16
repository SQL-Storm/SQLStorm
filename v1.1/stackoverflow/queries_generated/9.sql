-- {"query": "9.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 189} 
WITH cte_post_scores AS (
    SELECT p.Id, p.Score,
           DENSE_RANK() OVER (ORDER BY p.Score DESC) AS score_rank
    FROM Posts p
    WHERE p.PostTypeId = 1
),
cte_top_users AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           RANK() OVER (ORDER BY u.Reputation DESC) AS reputation_rank
    FROM Users u
),
cte_join_data AS (
    SELECT ps.Id AS PostId, ps.Score, ps.score_rank,
           tu.Id AS UserId, tu.DisplayName, tu.Reputation, tu.reputation_rank
    FROM cte_post_scores ps
    INNER JOIN cte_top_users tu ON ps.score_rank = tu.reputation_rank
)
SELECT jd.UserId, jd.DisplayName, jd.Reputation, jd.score_rank
FROM cte_join_data jd
ORDER BY jd.score_rank DESC, jd.reputation_rank ASC;