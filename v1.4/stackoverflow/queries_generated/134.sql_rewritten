-- {"query": "134.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1079} 
WITH RecentBumps AS (
  SELECT
    p.OwnerUserId,
    COUNT(*) AS BumpCount
  FROM Posts p
  JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 50
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(rb.BumpCount, 0) AS Bumps,
    (SELECT COUNT(*) FROM Posts pr WHERE pr.OwnerUserId = u.Id AND pr.CreationDate > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '365 days')) AS RecentPosts,
    (SELECT AVG(pr.Score) FROM Posts pr WHERE pr.OwnerUserId = u.Id) AS AvgPostScore,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgesCnt,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId IN (2, 11, 16)) AS VotesCast
  FROM Users u
  LEFT JOIN RecentBumps rb ON rb.OwnerUserId = u.Id
)
SELECT
  us.UserId,
  us.DisplayName,
  us.Reputation,
  us.RecentPosts,
  us.AvgPostScore,
  us.Bumps,
  us.BadgesCnt,
  us.VotesCast,
  p.Title AS TopPostTitle,
  p.Score AS TopPostScore,
  p.CreationDate AS TopPostDate,
  p.Id AS TopPostId,
  ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.RecentPosts DESC, us.AvgPostScore DESC) AS Rank
FROM UserStats us
LEFT JOIN Posts p ON p.OwnerUserId = us.UserId
  AND p.Score = (SELECT MAX(pr.Score) FROM Posts pr WHERE pr.OwnerUserId = us.UserId)
WHERE us.Reputation > 1000
ORDER BY Rank, us.UserId;