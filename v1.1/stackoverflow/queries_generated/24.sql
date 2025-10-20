-- {"query": "24.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 206} 
WITH user_statistics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COALESCE(COUNT(DISTINCT p.Id), 0) AS total_posts,
        COALESCE(SUM(v.VoteTypeId = 2), 0) AS total_upvotes,
        COALESCE(SUM(v.VoteTypeId = 3), 0) AS total_downvotes
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY u.Id
)

SELECT 
    us.Id AS user_id,
    us.DisplayName AS user_name,
    us.total_posts,
    us.total_upvotes,
    us.total_downvotes,
    COALESCE(SUM(CASE WHEN us.total_posts > 0 THEN 1 ELSE 0 END), 0) AS active_user_flag
FROM user_statistics us
GROUP BY us.Id, us.DisplayName
ORDER BY active_user_flag DESC, us.total_posts DESC;