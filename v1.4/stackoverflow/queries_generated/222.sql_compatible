WITH
UserPostStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Location,
    u.Reputation,
    MAX(p.LastActivityDate) AS LastActivityDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Location, u.Reputation
),
BadgeCounts AS (
  SELECT
    UserId,
    SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges
  GROUP BY UserId
),
RecentCommentSum AS (
  SELECT
    UserId,
    COUNT(*) AS RecentCommentCount
  FROM Comments
  WHERE CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7 days'
  GROUP BY UserId
),
TopLocationRanking AS (
  SELECT
    up.UserId,
    up.DisplayName,
    up.Location,
    up.Reputation,
    up.LastActivityDate,
    ROW_NUMBER() OVER (
      PARTITION BY COALESCE(up.Location, 'Unknown')
      ORDER BY up.Reputation DESC
    ) AS RankInLocation,
    -- Correlated subquery: number of posts by this user in the last 180 days
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = up.UserId AND p2.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days') AS RecentPosts
  FROM UserPostStats up
),
TopBadged AS (
  SELECT
    u.Id AS UserId,
    COALESCE(b.GoldBadges, 0) AS GoldBadges,
    COALESCE(b.SilverBadges, 0) AS SilverBadges,
    COALESCE(b.BronzeBadges, 0) AS BronzeBadges
  FROM Users u
  LEFT JOIN BadgeCounts b ON b.UserId = u.Id
),
Combined AS (
  -- Set 1: top reputation users with activity
  SELECT
    t.UserId,
    t.DisplayName,
    t.Location,
    t.Reputation,
    t.LastActivityDate,
    t.RankInLocation,
    b.GoldBadges,
    b.SilverBadges,
    b.BronzeBadges,
    t.RecentPosts,
    (t.DisplayName || ' (' || COALESCE(t.Location, 'Unknown') || ')') AS UserTag
  FROM TopLocationRanking t
  LEFT JOIN TopBadged b ON b.UserId = t.UserId
  WHERE t.RankInLocation <= 10

  UNION ALL

  -- Set 2: actively commenting users in last 7 days
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Location,
    u.Reputation,
    (SELECT MAX(p.LastActivityDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastActivityDate,
    NULL AS RankInLocation,
    COALESCE(b.GoldBadges, 0) AS GoldBadges,
    COALESCE(b.SilverBadges, 0) AS SilverBadges,
    COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7 days') AS RecentPosts,
    (u.DisplayName || ' [Active]') AS UserTag
  FROM Users u
  LEFT JOIN TopBadged b ON b.UserId = u.Id
  WHERE EXISTS (SELECT 1 FROM Comments c WHERE c.UserId = u.Id)
)
SELECT
  *
FROM Combined
ORDER BY Reputation DESC NULLS LAST
LIMIT 500;