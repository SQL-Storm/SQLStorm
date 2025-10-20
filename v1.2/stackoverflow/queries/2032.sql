WITH RecentActiveUsers AS (
  SELECT u.Id,
         u.DisplayName,
         u.Reputation,
         COUNT(p.Id) AS TotalPosts,
         COALESCE(SUM(p.Score), 0) AS PostsScore,
         COALESCE(SUM(p.ViewCount), 0) AS TotalViews
  FROM Users u
  LEFT JOIN Posts p
    ON p.OwnerUserId = u.Id
   AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365 days'
  WHERE u.Reputation > 1000
  GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT *
FROM RecentActiveUsers;