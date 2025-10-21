-- {"query": "195.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1581} 
WITH
-- Basic per-user aggregates from posts
UserPostStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(SUM(p.Score),0) AS TotalPostScore,
    COUNT(p.Id) AS PostCount,
    MAX(p.LastActivityDate) AS LastActivityDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
-- Badges per user
UserBadges AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    MAX(b.Class) AS MaxBadgeClass
  FROM Badges b
  GROUP BY b.UserId
),
-- Recent activity per user
RecentActivity AS (
  SELECT
    p.OwnerUserId AS UserId,
    MAX(p.LastActivityDate) AS LastActivity
  FROM Posts p
  GROUP BY p.OwnerUserId
),
-- Combine the above, resolve NULLs, and compute derived metrics
Combined AS (
  SELECT
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.TotalPostScore,
    up.PostCount,
    COALESCE(ba.BadgeCount, 0) AS BadgeCount,
    COALESCE(ra.LastActivity, up.LastAccessDate) AS LastActivityDate
  FROM UserPostStats up
  LEFT JOIN UserBadges ba ON ba.UserId = up.UserId
  LEFT JOIN RecentActivity ra ON ra.UserId = up.UserId
),
-- Set A: top users by Reputation then by TotalPostScore
TopUsers AS (
  SELECT
    c.UserId,
    c.DisplayName,
    c.Reputation,
    c.TotalPostScore,
    c.PostCount,
    c.BadgeCount,
    c.LastActivityDate,
    ROW_NUMBER() OVER (
      ORDER BY c.Reputation DESC
               , c.TotalPostScore DESC
               , c.PostCount DESC
               , c.LastActivityDate DESC
    ) AS RankA
  FROM Combined c
),
-- Set B: highly active users in the last 30 days with complex tag-like filtering
ActiveLast30 AS (
  SELECT
    p.OwnerUserId AS UserId,
    MAX(p.LastActivityDate) AS LastActivity,
    COUNT(*) AS PostsLast30,
    SUM(p.Score) AS ScoreLast30
  FROM Posts p
  WHERE p.LastActivityDate >= cast('2024-10-01' as date) - INTERVAL '30 days'
  GROUP BY p.OwnerUserId
),
ActiveUsers30 AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(al.ScoreLast30, 0) AS ScoreLast30,
    COALESCE(al.PostsLast30, 0) AS PostsLast30
  FROM Users u
  LEFT JOIN ActiveLast30 al ON al.UserId = u.Id
  WHERE COALESCE(al.PostsLast30, 0) > 0
),
-- Final union of sets A and B, with a consistent projection
Unioned AS (
  SELECT
    t.UserId,
    t.DisplayName,
    t.Reputation,
    t.TotalPostScore,
    t.PostCount,
    t.BadgeCount,
    t.LastActivityDate,
    t.RankA
  FROM TopUsers t

  UNION ALL

  SELECT
    au.UserId,
    au.DisplayName,
    au.Reputation,
    NULL AS TotalPostScore,
    NULL AS PostCount,
    NULL AS BadgeCount,
    au.LastAccessDate AS LastActivityDate,
    NULL AS RankA
  FROM ActiveUsers30 au
)
SELECT
  UserId,
  DisplayName,
  Reputation,
  TotalPostScore,
  PostCount,
  BadgeCount,
  LastActivityDate,
  RankA,
  -- Correlated subquery: how many positive-score posts this user had created in the last 90 days
  (
    SELECT COUNT(*) FROM Posts p
    WHERE p.OwnerUserId = Unioned.UserId
      AND p.Score > 0
      AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '90 days'
  ) AS PositivePostsLast90
FROM Unioned
ORDER BY COALESCE(RankA, 999999) ASC
LIMIT 200;