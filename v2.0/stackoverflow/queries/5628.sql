-- {"query": "5628.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1294} 
WITH
-- sample windowed aggregate: per user, recent activity and scoring dynamics
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN v.BountyAmount ELSE 0 END) AS BountiesEarned,
    MAX(p.LastActivityDate) AS LastActivityDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE u.AccountId IS NOT NULL
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
-- correlated subquery: top 3 most upvoted posts per user
TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
-- a complex self-join exploring relationships via PostLinks
LinkedPairs AS (
  SELECT
    pl.Id,
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    p1.OwnerUserId AS SrcOwner,
    p2.OwnerUserId AS DstOwner,
    p1.Score AS SrcScore,
    p2.Score AS DstScore
  FROM PostLinks pl
  JOIN Posts p1 ON pl.PostId = p1.Id
  JOIN Posts p2 ON pl.RelatedPostId = p2.Id
  WHERE pl.LinkTypeId IN (1,3)
),
-- advanced predicate: posts with high ratio of Upvotes to Downvotes among recent activity
HighEngagement AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    COALESCE(v2.UpModCount,0) AS UpModCount,
    COALESCE(v3.DownModCount,0) AS DownModCount,
    CASE
      WHEN p.ViewCount = 0 THEN 0
      ELSE (CAST(p.Score AS float) / NULLIF(p.ViewCount,0))
    END AS ScorePerView
  FROM Posts p
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS UpModCount
    FROM Votes
    WHERE VoteTypeId = 2
    GROUP BY PostId
  ) v2 ON v2.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS DownModCount
    FROM Votes
    WHERE VoteTypeId = 3
    GROUP BY PostId
  ) v3 ON v3.PostId = p.Id
  WHERE p.LastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
),
-- final assembly: combine statistical profile, top posts, and engagement with a complex filter
BenchmarkSuite AS (
  SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.CreationDate,
    us.LastAccessDate,
    us.PostCount,
    us.UpvotesReceived,
    us.DownvotesReceived,
    us.BountiesEarned,
    us.LastActivityDate,
    tp.PostId AS TopPostId,
    tp.Title AS TopPostTitle,
    tp.Score AS TopPostScore,
    tp.ViewCount AS TopPostViews,
    tp.CreationDate AS TopPostCreated
  FROM UserStats us
  LEFT JOIN (
    SELECT *
    FROM TopPosts
    WHERE rn = 1
  ) tp ON tp.OwnerUserId = us.UserId
  LEFT JOIN (
    SELECT OwnerUserId, MAX(CASE WHEN Score > 0 THEN Score END) AS MaxScore
    FROM Posts
    GROUP BY OwnerUserId
  ) tpm ON tpm.OwnerUserId = us.UserId
  WHERE us.Reputation > 100
    AND (tp.PostId IS NULL OR tp.Score > 0)
),
-- final selection with advanced predicates and a set operation demonstration (UNION ALL with a synthetic second dataset)
FinalA AS (
  SELECT
    bs.UserId,
    bs.DisplayName,
    bs.Reputation,
    bs.PostCount,
    bs.TopPostId,
    bs.TopPostTitle,
    bs.TopPostScore,
    bs.TopPostViews
  FROM BenchmarkSuite bs
  WHERE bs.TopPostScore IS NOT NULL
  UNION ALL
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    0 AS PostCount,
    NULL AS TopPostId,
    NULL AS TopPostTitle,
    NULL AS TopPostScore,
    NULL AS TopPostViews
  FROM Users u
  WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
)
SELECT
  f.UserId,
  f.DisplayName,
  f.Reputation,
  f.PostCount,
  f.TopPostId,
  f.TopPostTitle,
  f.TopPostScore,
  f.TopPostViews,
  -- window function: rank users by combined engagement
  RANK() OVER (ORDER BY f.Reputation DESC, f.PostCount DESC, f.TopPostScore DESC NULLS LAST) AS UserRank,
  -- additional derived metrics
  (SELECT COUNT(*) FROM Badges b WHERE b.UserId = f.UserId) AS BadgeCount,
  (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = f.UserId)) AS TotalBountyEngaged
FROM FinalA f
ORDER BY UserRank
LIMIT 100;