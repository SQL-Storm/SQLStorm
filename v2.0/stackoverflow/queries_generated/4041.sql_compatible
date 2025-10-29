WITH RankedPostEdits AS (
  SELECT
    ph.PostId,
    ph.UserId,
    ph.CreationDate,
    ph.PostHistoryTypeId,
    ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserPostActivity AS (
  SELECT
    p.OwnerUserId,
    COUNT(p.Id) AS NumPosts,
    SUM(p.Score) AS TotalScore,
    AVG(CAST(p.AnswerCount AS DECIMAL(10, 2))) AS AvgAnswerCount,
    MAX(p.CreationDate) AS LastPostCreationDate,
    COUNT(DISTINCT c.Id) AS NumComments
  FROM Posts p
  LEFT JOIN Comments c
    ON p.Id = c.PostId
  WHERE p.OwnerUserId IS NOT NULL AND p.PostTypeId = 1
  GROUP BY p.OwnerUserId
),
UserReputationChanges AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    (
      SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2
    ) AS TotalUpVotes,
    (
      SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3
    ) AS TotalDownVotes,
    (
      SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 8
    ) AS TotalBountyGiven
  FROM Users u
  WHERE u.Reputation > 1000
)
SELECT
  u.DisplayName,
  upa.NumPosts,
  upa.TotalScore,
  upa.AvgAnswerCount,
  urc.TotalUpVotes,
  urc.TotalDownVotes,
  urc.TotalBountyGiven,
  CASE
    WHEN u.WebsiteUrl IS NOT NULL AND CHAR_LENGTH(u.WebsiteUrl) > 5 THEN 'Has Website'
    WHEN u.Location IS NOT NULL THEN 'Has Location'
    ELSE 'No Profile Details'
  END AS ProfileStatus,
  CASE
    WHEN rpe.UserId IS NOT NULL THEN 'Edited Posts'
    ELSE 'Did Not Edit Posts'
  END AS EditActivity,
  COALESCE(upa.NumComments, 0) AS CommentsMade,
  CASE
    WHEN upa.LastPostCreationDate > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days') THEN 'Active Recently'
    ELSE 'Inactive Long Term'
  END AS ActivityLevel
FROM Users u
JOIN UserPostActivity upa
  ON u.Id = upa.OwnerUserId
JOIN UserReputationChanges urc
  ON u.Id = urc.UserId
LEFT JOIN RankedPostEdits rpe
  ON u.Id = rpe.UserId AND rpe.rn = 1
WHERE upa.TotalScore > 0 AND urc.TotalUpVotes > urc.TotalDownVotes

UNION

SELECT
  u.DisplayName,
  0 AS NumPosts,
  0 AS TotalScore,
  0.0 AS AvgAnswerCount,
  urc.TotalUpVotes,
  urc.TotalDownVotes,
  urc.TotalBountyGiven,
  CASE
    WHEN u.WebsiteUrl IS NOT NULL AND CHAR_LENGTH(u.WebsiteUrl) > 5 THEN 'Has Website'
    WHEN u.Location IS NOT NULL THEN 'Has Location'
    ELSE 'No Profile Details'
  END AS ProfileStatus,
  CASE
    WHEN rpe.UserId IS NOT NULL THEN 'Edited Posts'
    ELSE 'Did Not Edit Posts'
  END AS EditActivity,
  0 AS CommentsMade,
  CASE
    WHEN u.LastAccessDate > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days') THEN 'Active Recently'
    ELSE 'Inactive Long Term'
  END AS ActivityLevel
FROM Users u
JOIN UserReputationChanges urc
  ON u.Id = urc.UserId
LEFT JOIN RankedPostEdits rpe
  ON u.Id = rpe.UserId AND rpe.rn = 1
WHERE u.Id NOT IN (
    SELECT OwnerUserId
    FROM Posts
    WHERE PostTypeId = 1 AND OwnerUserId IS NOT NULL
  )
  AND urc.TotalUpVotes > 50;