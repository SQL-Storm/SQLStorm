WITH cte_post_scores AS (
    SELECT
        p.Id AS post_id,
        COALESCE(p.Score, 0) AS post_score,
        COUNT(v.Id) AS vote_count,
        p.OwnerUserId AS owner_user_id
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, COALESCE(p.Score, 0), p.OwnerUserId
),

cte_max_score_per_user AS (
    SELECT
        u.Id AS user_id,
        MAX(ps.post_score) AS max_post_score
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (
        SELECT Id AS post_id, COALESCE(Score, 0) AS post_score
        FROM Posts
        WHERE PostTypeId IN (1, 2)
    ) ps ON p.Id = ps.post_id
    WHERE u.Reputation > 1000
    GROUP BY u.Id
)

SELECT
    u.DisplayName,
    u.Reputation,
    COALESCE(MAX(ps.post_score), 0) AS max_post_score,
    COALESCE(SUM(ps.vote_count), 0) AS total_votes
FROM Users u
LEFT JOIN cte_max_score_per_user ms ON u.Id = ms.user_id
LEFT JOIN cte_post_scores ps ON u.Id = ps.owner_user_id
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(ps.post_id) > 5
ORDER BY total_votes DESC, max_post_score DESC;