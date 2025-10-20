-- {"query": "200.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1824} 
WITH UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS PostCount,
    SUM(COALESCE(p.Score, 0)) AS ScoreSum,
    COUNT(v.*) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteCount,
    MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserBadges AS (
  SELECT
    UserId,
    COUNT(*) AS BadgeCount
  FROM Badges
  GROUP BY UserId
)
SELECT
  to_char(now(), 'YYYY-MM-DD') AS QueryDate,
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.PostCount,
  ua.ScoreSum,
  COALESCE(ub.BadgeCount, 0) AS BadgeCount,
  (ua.Reputation * 0.5
   + COALESCE(ua.ScoreSum, 0) * 0.3
   + COALESCE(ua.UpVoteCount, 0) * 0.2
   + COALESCE(ub.BadgeCount, 0) * 1.5) AS PerformanceScore,
  ua.LastPostDate
FROM UserActivity ua
LEFT JOIN UserBadges ub ON ub.UserId = ua.UserId
WHERE ua.LastPostDate >= NOW() - INTERVAL '365 days'
ORDER BY PerformanceScore DESC
LIMIT 200;