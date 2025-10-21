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
  LEFT JOIN LinkActivity la ON la.PostId = c.UserId
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
  CASE
    WHEN a.LastPostDate IS NULL THEN NULL
    ELSE (EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - a.LastPostDate)) / 3600.0)
  END AS HoursSinceLastPost,
  CASE
    WHEN a.LastVoteDate IS NULL THEN NULL
    ELSE CAST(a.LastVoteDate AS TIMESTAMP WITH TIME ZONE)
  END AS LastVoteDateISO,
  (COALESCE(a.ScoreSum, 0) * 2 + COALESCE(a.PostCount, 0) * 3 + COALESCE(a.BadgeCount, 0) * 5 + COALESCE(a.CloseVotes, 0)) AS BenchmarkScore
FROM Aggregated a
ORDER BY BenchmarkScore DESC NULLS LAST
LIMIT 100;