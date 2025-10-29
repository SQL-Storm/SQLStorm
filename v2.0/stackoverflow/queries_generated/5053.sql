-- {"query": "5053.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1033} 
WITH
-- 1) Top users by reputation with recent activity and badge diversity
UserAgg AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn_user
  FROM Users u
),
-- 2) Recent posts per user (last 30 days)
RecentPosts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.PostTypeId,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_post
  FROM Posts p
  WHERE p.CreationDate >= current_timestamp - interval '30 days'
),
-- 3) Badge diversity per user (count of distinct badge names)
BadgeDiversity AS (
  SELECT
    b.UserId,
    COUNT(DISTINCT b.Name) AS DistinctBadges
  FROM Badges b
  GROUP BY b.UserId
),
-- 4) Activity score combining posts, comments, and votes with NULL-safe expressions
Activity AS (
  SELECT
    u.Id AS UserId,
    COALESCE(SUM(p.Score),0) AS PostScore,
    COALESCE(SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END),0) AS CommentCount,
    COALESCE(SUM(v.BountyAmount),0) AS BountiesAwarded
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id
),
-- 5) Complex correlated subquery: for each post, latest related post via LinkType 'Duplicate' or 'Linked'
PostLinksLatest AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    (SELECT p2.CreationDate
     FROM Posts p2 WHERE p2.Id = pl.RelatedPostId) AS RelatedCreationDate
  FROM PostLinks pl
  WHERE pl.LinkTypeId IN (1,3) -- Linked or Duplicate
),
-- 6) Windowed rollup: cumulative counts of posts per post type for last 60 days
PostTypeRolling AS (
  SELECT
    p.PostTypeId,
    COUNT(*) OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.CreationDate
      ROWS BETWEEN 59 PRECEDING AND CURRENT ROW
    ) AS RollingCount60
  FROM Posts p
  WHERE p.CreationDate >= current_timestamp - interval '60 days'
)
SELECT
  -- user core info
  u.UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate,
  -- recent activity flags
  (SELECT COUNT(*) FROM Posts pr WHERE pr.OwnerUserId = u.UserId AND pr.CreationDate >= current_timestamp - interval '7 days') AS PostsLast7d,
  (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.UserId AND c.CreationDate >= current_timestamp - interval '7 days') AS CommentsLast7d,
  (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.UserId AND v.CreationDate >= current_timestamp - interval '7 days') AS VotesLast7d,
  -- top post in last 7 days by score
  (
    SELECT p.Title
    FROM Posts p
    WHERE p.OwnerUserId = u.UserId AND p.CreationDate >= current_timestamp - interval '7 days'
    ORDER BY p.Score DESC, p.CreationDate DESC
    LIMIT 1
  ) AS TopPost7dTitle,
  -- badge diversity
  bd.DistinctBadges,
  -- aggregated activity
  a.PostScore,
  a.CommentCount,
  a.BountiesAwarded,
  -- latest related post via links
  (SELECT RelatedPostId
   FROM PostLinksLatest pll
   WHERE pll.PostId = (SELECT MAX(pl.PostId) FROM PostLinks pl WHERE pl.PostId = u.UserId)
   LIMIT 1) AS LatestLinkedPostId,
  -- rolling count per post type (60-day)
  (SELECT SUM(rc.RollingCount60) FROM PostTypeRolling rc WHERE rc.PostTypeId = 1) AS RollingQuestions60
FROM
  Users u
  LEFT JOIN BadgeDiversity bd ON bd.UserId = u.Id
  LEFT JOIN Activity a ON a.UserId = u.Id
ORDER BY u.Reputation DESC, u.LastAccessDate DESC
LIMIT 100;