-- {"query": "182.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2234} 
WITH UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreated,
    COALESCE(pn.LastPostDate, u.CreationDate) AS LastActive
  FROM Users u
  LEFT JOIN (
    SELECT OwnerUserId, MAX(CreationDate) AS LastPostDate
    FROM Posts
    GROUP BY OwnerUserId
  ) pn ON pn.OwnerUserId = u.Id
),
PostAgg AS (
  SELECT OwnerUserId,
         COUNT(*) AS PostCount,
         SUM(Score) AS ScoreSum,
         AVG(CASE WHEN Score IS NULL THEN 0 ELSE Score END) AS AvgScore
  FROM Posts
  GROUP BY OwnerUserId
),
BadgeCount AS (
  SELECT UserId, COUNT(*) AS Badges
  FROM Badges
  GROUP BY UserId
),
RecentPosts AS (
  SELECT p.Id AS PostId, p.OwnerUserId, p.Title, p.CreationDate,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
),
LatestPostComments AS (
  SELECT c.PostId, COUNT(*) AS CommentCount
  FROM Comments c
  GROUP BY c.PostId
)
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.UserCreated,
  ua.LastActive,
  pa.PostCount,
  pa.ScoreSum,
  bc.Badges,
  lp.Title AS LatestPostTitle,
  lp.CreationDate AS LatestPostDate,
  COALESCE(lpc.CommentCount, 0) AS LatestPostCommentCount,
  ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC NULLS LAST, ua.LastActive DESC NULLS LAST) AS UserRank
FROM UserActivity ua
LEFT JOIN PostAgg pa ON pa.OwnerUserId = ua.UserId
LEFT JOIN BadgeCount bc ON bc.UserId = ua.UserId
LEFT JOIN RecentPosts lp ON lp.OwnerUserId = ua.UserId AND lp.rn = 1
LEFT JOIN LatestPostComments lpc ON lpc.PostId = lp.PostId
UNION ALL
SELECT
  NULL AS UserId,
  'Total' AS DisplayName,
  SUM(ua.Reputation) AS Reputation,
  NULL AS UserCreated,
  NULL AS LastActive,
  SUM(COALESCE(pa.PostCount, 0)) AS PostCount,
  SUM(COALESCE(pa.ScoreSum, 0)) AS ScoreSum,
  SUM(COALESCE(bc.Badges, 0)) AS Badges,
  NULL AS LatestPostTitle,
  NULL AS LatestPostDate,
  0 AS LatestPostCommentCount,
  NULL AS UserRank
FROM Users u
LEFT JOIN UserActivity ua ON ua.UserId = u.Id
LEFT JOIN PostAgg pa ON pa.OwnerUserId = ua.UserId
LEFT JOIN BadgeCount bc ON bc.UserId = ua.UserId
LEFT JOIN RecentPosts lp ON lp.OwnerUserId = ua.UserId AND lp.rn = 1
LEFT JOIN LatestPostComments lpc ON lpc.PostId = lp.PostId
ORDER BY UserRank NULLS LAST, UserId NULLS LAST
LIMIT 200;