-- {"query": "47.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 210} 
WITH recent_posts AS (
    SELECT p.Id AS PostId, p.Title, p.Tags, p.CreationDate, p.OwnerUserId
    FROM Posts p
    WHERE p.CreationDate > NOW() - INTERVAL '30 days'
), high_score_posts AS (
    SELECT rp.PostId, rp.Title, rp.Tags, rp.CreationDate, rp.OwnerUserId, p.Score
    FROM recent_posts rp
    JOIN Posts p ON rp.PostId = p.Id
    WHERE p.Score > 50
), active_users AS (
    SELECT up.OwnerUserId, COUNT(DISTINCT up.PostId) AS NumPosts
    FROM high_score_posts up
    WHERE up.CreationDate > NOW() - INTERVAL '7 days'
    GROUP BY up.OwnerUserId
    HAVING COUNT(DISTINCT up.PostId) > 3
)
SELECT au.OwnerUserId, au.NumPosts, u.DisplayName
FROM active_users au
JOIN Users u ON au.OwnerUserId = u.Id
ORDER BY au.NumPosts DESC, u.DisplayName;