-- {"query": "5292.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1031} 
WITH
-- per-user aggregate with windowed stats
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    -- total posts by user
    COUNT(p.Id) AS PostCount,
    -- sum of post scores
    SUM(COALESCE(p.Score,0)) AS ScoreSum,
    -- average post age in days (from creation to now)
    AVG(DATEDIFF(second, p.CreationDate, CURRENT_TIMESTAMP) / 86400.0) AS AvgPostAgeDays
  FROM
    Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Location, u.Views, u.UpVotes, u.DownVotes
),
-- recent activity per user with correlated subquery and window function
RecentActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate AS PostCreationDate,
    p.LastActivityDate,
    p.Title,
    p.Tags,
    ROW_NUMBER() OVER (
      PARTITION BY u.Id
      ORDER BY p.LastActivityDate DESC NULLS LAST, p.CreationDate DESC
    ) AS rn
  FROM
    Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE
    p.Id IS NOT NULL
),
-- example of advanced correlation: for each post, compute a derived "hotness" score
HotPosts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.ViewCount,
    p.Score,
    p.LastActivityDate,
    -- a somewhat synthetic hotness score using multiple factors
    (COALESCE(p.Score,0) * 1.5
     + COALESCE(p.ViewCount,0) * 0.01
     + EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - p.CreationDate)) * -0.0001
     + COALESCE(v.BountyAmount,0) * 0.7
    ) AS Hotness
  FROM
    Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 8 -- BountyStart as a proxy for activity
  WHERE
    p.PostTypeId IN (1,2) -- questions and answers
),
-- correlated subquery: for each user, find the most recent closed post with a non-null close reason
RecentClosed AS (
  SELECT
    u.Id AS UserId,
    cr.PostId,
    cr.CloseReasonId,
    cr.ClosedDate
  FROM
    Users u
    JOIN Posts cr ON cr.OwnerUserId = u.Id
  WHERE
    cr.ClosedDate IS NOT NULL
  ORDER BY cr.ClosedDate DESC
  LIMIT 100
)
SELECT
  -- top-level shape: join stats and hot posts with some filters to produce rich benchmarking data
  u.UserId,
  u.DisplayName,
  s.PostCount,
  s.ScoreSum,
  s.AvgPostAgeDays,
  -- recent activity features
  ARRAY_AGG(DISTINCT ra.PostId ORDER BY ra.PostCreationDate DESC NULLS LAST) FILTER (WHERE ra.PostId IS NOT NULL) AS RecentPostIds,
  -- hotness snapshot
  hp.PostId AS HotPostId,
  hp.Title AS HotPostTitle,
  hp.Score AS HotPostScore,
  hp.ViewCount AS HotPostViews,
  hp.Hotness,
  -- recent closed post snippet
  rc.PostId AS ClosedPostId,
  rc.CloseReasonId,
  rc.ClosedDate
FROM
  UserStats s
  JOIN RecentActivity ra ON ra.UserId = s.UserId
  LEFT JOIN HotPosts hp ON hp.OwnerUserId = s.UserId
  LEFT JOIN RecentClosed rc ON rc.UserId = s.UserId
  JOIN Users u ON u.Id = s.UserId
WHERE
  -- benchmark-oriented predicates: include a mix of NULL-safe and complex filters
  (s.PostCount > 0 OR hp.PostId IS NOT NULL)
  AND (rc.ClosedDate IS NULL OR rc.ClosedDate > CURRENT_TIMESTAMP - INTERVAL '90 days')
GROUP BY
  u.UserId, u.DisplayName, s.PostCount, s.ScoreSum, s.AvgPostAgeDays,
  hp.PostId, hp.Title, hp.Score, hp.ViewCount, hp.Hotness,
  rc.PostId, rc.CloseReasonId, rc.ClosedDate
ORDER BY
  hp.Hotness DESC NULLS LAST
LIMIT 200;