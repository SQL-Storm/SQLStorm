WITH user_reputation_rank AS (
    SELECT Id, Reputation, 
           ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS reputation_rank
    FROM Users
),
top_users AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           COALESCE(r.reputation_rank, 0) AS ranking
    FROM Users u
    LEFT JOIN user_reputation_rank r ON u.Id = r.Id
    WHERE u.Reputation > 10000
),
post_activity AS (
    SELECT p.OwnerUserId, 
           COUNT(DISTINCT p.Id) AS total_posts,
           SUM(p.ViewCount) AS total_views
    FROM Posts p
    GROUP BY p.OwnerUserId
),
top_users_activity AS (
    SELECT tu.Id, tu.DisplayName, tu.Reputation, tu.ranking, pa.total_posts, pa.total_views
    FROM top_users tu
    LEFT JOIN post_activity pa ON tu.Id = pa.OwnerUserId
)
SELECT tu.DisplayName, tu.Reputation, tu.ranking,
       COALESCE(tu.total_posts, 0) AS total_posts,
       COALESCE(tu.total_views, 0) AS total_views
FROM top_users_activity tu
ORDER BY tu.ranking DESC;