-- {"query": "149.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1961} 
WITH UserTotals AS (
  SELECT
    u.Id AS UserId,
    SUM(p.Score) AS TotalScore,
    AVG(p.Score) AS AvgScore,
    COUNT(p.Id) AS PostsCount,
    MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
BadgeCounts AS (
  SELECT
    UserId,
    COUNT(*) AS BadgeCount
  FROM Badges
  GROUP BY UserId
),
LastVote AS (
  SELECT
    UserId,
    MAX(CreationDate) AS LastVoteDate
  FROM Votes
  GROUP BY UserId
),
RecentActivity AS (
  SELECT
    u.Id AS UserId,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY v.CreationDate DESC) AS rn,
    v.CreationDate AS LastVoteDate,
    v.VoteTypeId
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(ut.TotalScore, 0) AS TotalScore,
  COALESCE(ut.AvgScore, 0) AS AvgScore,
  COALESCE(ut.PostsCount, 0) AS PostsCount,
  ut.LastPostDate,
  COALESCE(bc.BadgeCount, 0) AS BadgeCount,
  lu.LastVoteDate,
  PERCENT_RANK() OVER (ORDER BY COALESCE(ut.TotalScore, 0) DESC) AS ScorePercent
FROM Users u
LEFT JOIN UserTotals ut ON ut.UserId = u.Id
LEFT JOIN BadgeCounts bc ON bc.UserId = u.Id
LEFT JOIN LastVote lu ON lu.UserId = u.Id
LEFT JOIN (
  SELECT UserId, MAX(CreationDate) AS LastVoteDate
  FROM Votes
  GROUP BY UserId
) AS lu2 ON lu2.UserId = u.Id
JOIN LATERAL (
  SELECT lu2.LastVoteDate
) AS lv ON TRUE
WHERE u.Reputation > 0
ORDER BY ScorePercent DESC, u.Id
LIMIT 100;