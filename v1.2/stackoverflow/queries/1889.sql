WITH Top30Users AS (
  SELECT u.Id AS user_id,
         u.DisplayName AS displayname,
         cluster_users.rank_pos AS rank_within_cluster
  FROM Users u
  JOIN (
    SELECT UserId,
           row_number() OVER (PARTITION BY cnt_cluster ORDER BY Reputation DESC) AS rank_pos
    FROM (
      SELECT u.Id AS UserId,
             u.Reputation,
             dense_rank() OVER (ORDER BY FameCluster DESC) AS cnt_cluster
      FROM (
        SELECT Id,
               Reputation,
               ntile(10) OVER (ORDER BY Reputation DESC) AS rid,
               ntile(300) OVER (ORDER BY Reputation DESC) AS FameCluster
        FROM Users
        WHERE Id IS NOT NULL
      ) u
    ) cluster_users
  ) cluster_users ON cluster_users.UserId = u.Id
)
SELECT *
FROM Top30Users;