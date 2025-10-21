WITH UserPostStats AS (
  SELECT
    p.OwnerUserId AS UserId,
    COUNT(*) AS PostCount,
    SUM(COALESCE(p.Score, 0)) AS ScoreSum,
    AVG(COALESCE(p.Score, 0)) AS ScoreAvg,
    MAX(COALESCE(p.LastActivityDate, p.CreationDate)) AS LastActivity
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId
),
UserVoteStats AS (
  SELECT
    v.UserId,
    COUNT(*) AS VoteActions,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCast,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCast
  FROM Votes v
  GROUP BY v.UserId
),
BadgeCounts AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgesEarned,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
  FROM Badges b
  GROUP BY b.UserId
)
SELECT
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  u.Location,
  COALESCE(ups.PostCount, 0) AS PostCount,
  COALESCE(ups.ScoreSum, 0) AS ScoreSum,
  COALESCE(ups.ScoreAvg, 0) AS ScoreAvg,
  COALESCE(ups.LastActivity, u.CreationDate) AS LastActivityDate,
  COALESCE(uvs.VoteActions, 0) AS TotalVotesOnSite,
  COALESCE(uvs.UpVotesCast, 0) AS UpVotesCast,
  COALESCE(uvs.DownVotesCast, 0) AS DownVotesCast,
  COALESCE(bc.BadgesEarned, 0) AS BadgesEarned,
  COALESCE(bc.GoldBadges, 0) AS GoldBadges
FROM Users u
LEFT JOIN UserPostStats ups ON ups.UserId = u.Id
LEFT JOIN UserVoteStats uvs ON uvs.UserId = u.Id
LEFT JOIN BadgeCounts bc ON bc.UserId = u.Id
WHERE u.AccountId IS NOT NULL
ORDER BY u.Reputation DESC, LastActivityDate DESC
OFFSET 0 ROWS FETCH NEXT 200 ROWS ONLY;