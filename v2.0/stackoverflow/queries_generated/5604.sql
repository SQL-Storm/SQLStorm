-- {"query": "5604.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1132} 
WITH
-- 1) Compute per-user activity: counts of posts, comments, votes, and badges
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    -- posts authored by user
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostCount,
    -- comments authored by user
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentCount,
    -- upvotes cast by user
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'UpMod')) AS UpVotesCast,
    -- downvotes cast by user
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'DownMod')) AS DownVotesCast,
    -- badges earned by user
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount
  FROM Users u
),
-- 2) Recent post activity with window functions: rolling sums by day for user's posts
DailyUserActivity AS (
  SELECT
    p.OwnerUserId AS UserId,
    DATE(p.CreationDate) AS CreationDay,
    COUNT(*) AS PostsOnDay,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoresOnDay,
    SUM(CASE WHEN p.ViewCount > 1000 THEN 1 ELSE 0 END) AS HighViewPosts
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId, DATE(p.CreationDate)
),
-- 3) Correlated subquery: for each user, find the most controversial post (max abs(score))
MostControversialPost AS (
  SELECT
    p.OwnerUserId AS UserId,
    p.Id AS PostId,
    p.Title,
    p.Score,
    ABS(p.Score) AS AbsScore
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY ABS(p.Score) DESC) = 1
),
-- 4) Complex post-link digest: number of related posts with each LinkType
LinkTypeDigest AS (
  SELECT
    pl.PostId,
    lt.Name AS LinkTypeName,
    COUNT(*) AS LinkCount
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  GROUP BY pl.PostId, lt.Name
),
-- 5) Synthesis: build a rich per-user benchmarking row
BenchmarkRow AS (
  SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    COALESCE(us.PostCount, 0) AS PostCount,
    COALESCE(us.CommentCount, 0) AS CommentCount,
    COALESCE(us.UpVotesCast, 0) AS UpVotesCast,
    COALESCE(us.DownVotesCast, 0) AS DownVotesCast,
    COALESCE(us.BadgeCount, 0) AS BadgeCount,
    -- last 7 days activity aggregates
    (SELECT SUM(PostsOnDay) FROM DailyUserActivity dua WHERE dua.UserId = us.UserId AND dua.CreationDay >= CURRENT_DATE - INTERVAL '6 days') AS PostsLast7Days,
    (SELECT SUM(PositiveScoresOnDay) FROM DailyUserActivity dua WHERE dua.UserId = us.UserId AND dua.CreationDay >= CURRENT_DATE - INTERVAL '6 days') AS PositiveScoresLast7Days,
    (SELECT SUM(HighViewPosts) FROM DailyUserActivity dua WHERE dua.UserId = us.UserId AND dua.CreationDay >= CURRENT_DATE - INTERVAL '6 days') AS HighViewPostsLast7Days,
    -- most controversial post
    mcp.PostId AS MostControversialPostId,
    mcp.Title AS MostControversialPostTitle,
    mcp.Score AS MostControversialPostScore,
    -- total links from user's posts by type
    (SELECT SUM(LinkCount) FROM LinkTypeDigest ltd WHERE ltd.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = us.UserId)) AS TotalLinkedPostCount,
    -- latest edit date on user's posts (most recent activity)
    (SELECT MAX(p.LastActivityDate) FROM Posts p WHERE p.OwnerUserId = us.UserId) AS LastPostActivityDate
  FROM Users us
  LEFT JOIN DailyUserActivity dua ON dua.UserId = us.UserId
  LEFT JOIN MostControversialPost mcp ON mcp.UserId = us.UserId
)
SELECT
  br.UserId,
  br.DisplayName,
  br.Reputation,
  br.PostCount,
  br.CommentCount,
  br.UpVotesCast,
  br.DownVotesCast,
  br.BadgeCount,
  br.PostsLast7Days,
  br.PositiveScoresLast7Days,
  br.HighViewPostsLast7Days,
  br.MostControversialPostId,
  br.MostControversialPostTitle,
  br.MostControversialPostScore,
  br.TotalLinkedPostCount,
  br.LastPostActivityDate
FROM BenchmarkRow br
ORDER BY br.Reputation DESC, br.PostCount DESC, br.LastPostActivityDate DESC;