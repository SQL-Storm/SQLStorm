WITH
RecentActivity AS (
  SELECT
     u.Id AS UserId,
     u.DisplayName,
     u.Reputation,
     (SELECT COUNT(*) FROM Posts ps WHERE ps.OwnerUserId = u.Id) AS PostCount,
     (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount
  FROM Users u
  WHERE u.LastAccessDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days'
),
TopPostsPerAuthor AS (
  SELECT
     u.Id AS UserId,
     u.DisplayName,
     p.Id AS PostId,
     p.Title,
     p.Score,
     ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.LastActivityDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
),
CompositeMetrics AS (
  SELECT ra.UserId, ra.DisplayName, ra.Reputation, ra.PostCount, ra.BadgeCount
  FROM RecentActivity ra
)
SELECT
  'Users by recent activity' AS Section,
  ra.UserId,
  ra.DisplayName,
  ra.Reputation,
  ra.PostCount,
  ra.BadgeCount,
  NULL AS PostId,
  NULL AS Title
FROM RecentActivity ra
WHERE ra.Reputation > 100 AND ra.PostCount > 0

UNION ALL

SELECT
  'Top posts by score per author' AS Section,
  tp.UserId,
  tp.DisplayName,
  NULL,
  NULL,
  NULL,
  tp.PostId,
  tp.Title
FROM TopPostsPerAuthor tp
WHERE tp.rn = 1

UNION ALL

SELECT
  'Composite metrics' AS Section,
  cm.UserId,
  cm.DisplayName,
  cm.Reputation,
  cm.PostCount,
  cm.BadgeCount,
  NULL AS PostId,
  NULL AS Title
FROM CompositeMetrics cm
ORDER BY Section, UserId;