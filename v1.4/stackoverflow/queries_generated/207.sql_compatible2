WITH
PostsAgg AS (
  SELECT p.OwnerUserId AS UserId,
         COUNT(*) AS TotalPosts,
         SUM(p.Score) AS ScoreSum,
         AVG(p.Score) AS AvgScore
  FROM Posts p
  GROUP BY p.OwnerUserId
),
VotesAgg AS (
  SELECT v.UserId AS UserId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpModVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownModVotes
  FROM Votes v
  GROUP BY v.UserId
),
BadgesAgg AS (
  SELECT b.UserId AS UserId,
         COUNT(*) AS BadgeCount,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
  FROM Badges b
  GROUP BY b.UserId
),
Recent30 AS (
  SELECT p.OwnerUserId AS UserId,
         COUNT(*) AS PostsLast30,
         SUM(p.Score) AS ScoreLast30,
         SUM(p.ViewCount) AS ViewsLast30
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
  GROUP BY p.OwnerUserId
),
TopPost AS (
  SELECT UserId, TopPostTitle, TopPostId
  FROM (
    SELECT p.OwnerUserId AS UserId,
           p.Title AS TopPostTitle,
           p.Id AS TopPostId,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) x
  WHERE rn = 1
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(pa.TotalPosts, 0) AS TotalPostsAllTime,
  COALESCE(pa.ScoreSum, 0) AS ScoreSumAllTime,
  COALESCE(pa.AvgScore, 0) AS AvgScoreAllTime,
  COALESCE(v.UpModVotes, 0) AS UpModVotes,
  COALESCE(v.DownModVotes, 0) AS DownModVotes,
  COALESCE(bd.BadgeCount, 0) AS BadgeCount,
  COALESCE(bd.GoldBadges, 0) AS GoldBadges,
  COALESCE(r30.PostsLast30, 0) AS PostsLast30,
  COALESCE(r30.ScoreLast30, 0) AS ScoreLast30,
  COALESCE(r30.ViewsLast30, 0) AS ViewsLast30,
  tp.TopPostTitle,
  tp.TopPostId,
  (SELECT MAX(p.LastActivityDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastActivityDateCorrelated,
  -- Standard SQL: derive initials without using dialect-specific initcap
  UPPER(SUBSTRING(COALESCE(u.DisplayName, ''), 1, 1)) ||
  LOWER(SUBSTRING(COALESCE(u.DisplayName, ''), 2, 1)) AS DisplayNameInitials
FROM Users u
LEFT JOIN PostsAgg pa ON pa.UserId = u.Id
LEFT JOIN VotesAgg v ON v.UserId = u.Id
LEFT JOIN BadgesAgg bd ON bd.UserId = u.Id
LEFT JOIN Recent30 r30 ON r30.UserId = u.Id
LEFT JOIN TopPost tp ON tp.UserId = u.Id
ORDER BY u.Reputation DESC
LIMIT 100;