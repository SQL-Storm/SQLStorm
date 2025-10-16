WITH user_statistics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COALESCE(COUNT(DISTINCT p.Id), 0) AS total_posts,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS total_upvotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS total_downvotes
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY u.Id, u.DisplayName
)

SELECT 
    us.Id AS user_id,
    us.DisplayName AS user_name,
    us.total_posts,
    us.total_upvotes,
    us.total_downvotes,
    COALESCE(SUM(CASE WHEN us.total_posts > 0 THEN 1 ELSE 0 END), 0) AS active_user_flag
FROM user_statistics us
GROUP BY us.Id, us.DisplayName, us.total_posts, us.total_upvotes, us.total_downvotes
ORDER BY active_user_flag DESC, us.total_posts DESC;