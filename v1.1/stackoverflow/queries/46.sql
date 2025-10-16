-- {"query": "46.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 241} 
WITH user_activity AS (
    SELECT
        u.Id AS user_id,
        u.DisplayName AS user_display_name,
        COUNT(DISTINCT p.Id) AS total_posts,
        COUNT(DISTINCT c.Id) AS total_comments,
        COUNT(DISTINCT v.Id) AS total_votes
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
)

SELECT
    ua.user_id,
    ua.user_display_name,
    ua.total_posts,
    ua.total_comments,
    ua.total_votes,
    SUM(p.Score) AS total_post_score,
    SUM(v.BountyAmount) AS total_bounty_amount
FROM user_activity ua
LEFT JOIN Posts p ON ua.user_id = p.OwnerUserId
LEFT JOIN Votes v ON ua.user_id = v.UserId
WHERE p.PostTypeId = 1 OR v.VoteTypeId = 8
GROUP BY ua.user_id, ua.user_display_name, ua.total_posts, ua.total_comments, ua.total_votes;