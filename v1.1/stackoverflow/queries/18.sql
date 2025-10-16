WITH ranked_users AS (
  SELECT Id, DisplayName, Reputation,
         ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
  FROM Users
),
top_badge_users AS (
  SELECT u.Id, u.DisplayName, r.rank, ba.Name AS BadgeName
  FROM ranked_users r
  JOIN Users u ON r.Id = u.Id
  JOIN Badges ba ON u.Id = ba.UserId
  WHERE ba.Class = 1 -- Gold badge
    AND ba.TagBased = FALSE -- Named badge (use standard SQL boolean)
),
post_activity AS (
  SELECT p.OwnerUserId AS UserId,
         COUNT(DISTINCT p.Id) AS NumPosts,
         COUNT(DISTINCT c.Id) AS NumComments,
         SUM(COALESCE(v.VoteTypeId, 0)) AS TotalVotes
  FROM Posts p
  LEFT JOIN Comments c ON p.Id = c.PostId
  LEFT JOIN Votes v ON p.Id = v.PostId
  GROUP BY p.OwnerUserId
)
SELECT tbu.DisplayName, tbu.rank, tbu.BadgeName, pa.NumPosts, pa.NumComments, pa.TotalVotes
FROM top_badge_users tbu
LEFT JOIN post_activity pa ON tbu.Id = pa.UserId
GROUP BY tbu.Id, tbu.DisplayName, tbu.rank, tbu.BadgeName, pa.NumPosts, pa.NumComments, pa.TotalVotes
ORDER BY tbu.rank DESC;