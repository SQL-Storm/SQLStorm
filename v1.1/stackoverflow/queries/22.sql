-- {"query": "22.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 211} 
WITH cte_post_counts AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS num_posts,
        SUM(p.Score) AS total_score
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers only
    GROUP BY p.OwnerUserId
),
cte_user_reputation AS (
    SELECT 
        u.Id,
        u.Reputation,
        b.Class
    FROM Users u
    JOIN Badges b ON u.Id = b.UserId
),
cte_combined_data AS (
    SELECT 
        pc.OwnerUserId,
        pc.num_posts,
        pc.total_score,
        ur.Reputation,
        ur.Class
    FROM cte_post_counts pc
    JOIN cte_user_reputation ur ON pc.OwnerUserId = ur.Id
)

SELECT 
    c.OwnerUserId,
    c.num_posts,
    c.total_score,
    c.Reputation,
    c.Class
FROM cte_combined_data c
ORDER BY c.Reputation DESC, c.total_score ASC;