WITH RankedUserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT c.Id) AS TotalComments,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceived,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC) AS RankByReputation,
    DENSE_RANK() OVER (PARTITION BY COALESCE(p.PostTypeId, -1) ORDER BY u.Reputation DESC) AS RankByPostTypeReputation
  FROM Users u
  LEFT JOIN Posts p
    ON u.Id = p.OwnerUserId
  LEFT JOIN Comments c
    ON u.Id = c.UserId
  LEFT JOIN Votes v
    ON u.Id = v.UserId
  WHERE
    u.CreationDate < (CAST('2024-10-01' AS date) - INTERVAL '1 year') AND u.Views > 1000
  GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(p.PostTypeId, -1)
), RecentPostEdits AS (
  SELECT
    ph.PostId,
    p.Title,
    p.PostTypeId,
    ph.UserId AS EditorUserId,
    u.DisplayName AS EditorDisplayName,
    ph.CreationDate AS EditDate,
    ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS EditRank
  FROM PostHistory ph
  JOIN Posts p
    ON ph.PostId = p.Id
  JOIN Users u
    ON ph.UserId = u.Id
  WHERE
    ph.PostHistoryTypeId IN (4, 5, 7, 8, 9) AND ph.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '90 days')
)
SELECT
  r.UserId,
  r.DisplayName,
  r.Reputation,
  r.TotalPosts,
  r.TotalComments,
  r.TotalUpVotesReceived,
  r.TotalDownVotesReceived,
  r.RankByReputation,
  CASE
    WHEN r.RankByPostTypeReputation <= 5 THEN 'Top Contributor for Post Type'
    ELSE 'Regular Contributor'
  END AS ReputationTier,
  (
    SELECT
      COUNT(*)
    FROM PostLinks pl
    WHERE
      pl.PostId = (
        SELECT
          p2.Id
        FROM Posts p2
        WHERE
          p2.OwnerUserId = r.UserId AND p2.PostTypeId = 1
        ORDER BY
          p2.CreationDate ASC
        LIMIT 1
      ) AND pl.LinkTypeId = 3
  ) AS DuplicateLinksCreated,
  CASE
    WHEN r.DisplayName LIKE '%John%' THEN 'Contains John'
    WHEN r.DisplayName LIKE '%Doe%' THEN 'Contains Doe'
    ELSE 'Other Name'
  END AS NameCategory,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM Badges b WHERE b.UserId = r.UserId AND b.Name = 'Famous Question'
    ) THEN 'Has Famous Question Badge'
    ELSE 'No Famous Question Badge'
  END AS BadgeStatus,
  COALESCE(rpe.EditorDisplayName, 'No Recent Edits') AS MostRecentEditor,
  rpe.EditDate AS LastEditTimestamp
FROM RankedUserActivity r
LEFT JOIN RecentPostEdits rpe
  ON r.UserId = rpe.EditorUserId AND rpe.EditRank = 1
WHERE
  (r.TotalPosts > 10 AND r.TotalComments > 5) OR r.Reputation > 50000
GROUP BY
  r.UserId,
  r.DisplayName,
  r.Reputation,
  r.TotalPosts,
  r.TotalComments,
  r.TotalUpVotesReceived,
  r.TotalDownVotesReceived,
  r.RankByReputation,
  r.RankByPostTypeReputation,
  rpe.EditorDisplayName,
  rpe.EditDate
ORDER BY
  r.RankByReputation
LIMIT 100;