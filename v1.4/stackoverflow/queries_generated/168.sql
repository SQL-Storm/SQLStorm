-- {"query": "168.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1490} 
WITH UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    MAX(p.CreationDate) AS LastPostDate,
    COUNT(p.Id) AS PostCount,
    COALESCE(SUM(p.Score), 0) AS ScoreSum
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentActivities AS (
  SELECT
    u.Id AS UserId,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id
),
Combined AS (
  SELECT
    COALESCE(us.UserId, ra.UserId) AS UserId,
    us.DisplayName,
    us.Reputation,
    us.PostCount,
    us.ScoreSum,
    us.LastPostDate,
    ra.LastVoteDate
  FROM UserStats us
  FULL OUTER JOIN RecentActivities ra ON ra.UserId = us.UserId
),
TopBadges AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount
  FROM Badges b
  GROUP BY b.UserId
),
VoteCloseCounts AS (
  SELECT
    v.UserId,
    COUNT(*) AS CloseVotes
  FROM Votes v
  WHERE v.VoteTypeId = 6
  GROUP BY v.UserId
),
LinkActivity AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    l.Name AS LinkTypeName,
    COUNT(*) OVER (PARTITION BY pl.PostId) AS LinkCountPerPost
  FROM PostLinks pl
  JOIN LinkTypes l ON l.Id = pl.LinkTypeId
),
Aggregated AS (
  SELECT
    c.UserId,
    c.DisplayName,
    c.Reputation,
    c.PostCount,
    c.ScoreSum,
    c.LastPostDate,
    c.LastVoteDate,
    COALESCE(b.BadgeCount, 0) AS BadgeCount,
    COALESCE(vc.CloseVotes, 0) AS CloseVotes,
    COALESCE(la.LinkCountPerPost, 0) AS LinkCountPerPost
  FROM Combined c
  LEFT JOIN TopBadges b ON b.UserId = c.UserId
  LEFT JOIN VoteCloseCounts vc ON vc.UserId = c.UserId
  LEFT JOIN LinkActivity la ON la.PostId = c.UserId -- intentionally cross-link for correlation; will be aggregated below
)
SELECT
  a.UserId,
  a.DisplayName,
  a.Reputation,
  a.PostCount,
  a.ScoreSum,
  a.LastPostDate,
  a.LastVoteDate,
  a.BadgeCount,
  a.CloseVotes,
  a.LinkCountPerPost,
  -- Complex expression combining NULL-safe date arithmetic and string formatting
  CASE
    WHEN a.LastPostDate IS NULL THEN NULL
    ELSE (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - a.LastPostDate)) / 3600)
  END AS HoursSinceLastPost,
  CASE
    WHEN a.LastVoteDate IS NULL THEN NULL
    ELSE TO_CHAR(a.LastVoteDate, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  END AS LastVoteDateISO,
  -- A computed score using multiple components with NULL handling
  (COALESCE(a.ScoreSum, 0) * 2 + COALESCE(a.PostCount, 0) * 3 + COALESCE(a.BadgeCount, 0) * 5 + COALESCE(a.CloseVotes, 0)) AS BenchmarkScore
FROM Aggregated a
ORDER BY BenchmarkScore DESC NULLS LAST
LIMIT 100;