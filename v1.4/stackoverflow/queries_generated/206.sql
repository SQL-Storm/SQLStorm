-- {"query": "206.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 6819} 
WITH ActiveUsers AS (
  SELECT
    u.Id AS UserId,
    COALESCE(u.DisplayName, 'Unknown') AS DisplayName,
    u.Reputation,
    u.LastAccessDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS UserRank
  FROM Users u
  WHERE u.Reputation > 1000
    AND u.LastAccessDate IS NOT NULL
),
AllMetrics AS (
  -- Post count per active user
  SELECT
    a.UserId,
    a.DisplayName,
    'PostCount' AS MetricKey,
    COUNT(p.Id) AS MetricValue,
    CONCAT_WS(' | ', a.DisplayName, 'posts=', COUNT(p.Id)) AS Detail,
    a.UserRank
  FROM ActiveUsers a
  LEFT JOIN Posts p ON p.OwnerUserId = a.UserId
  GROUP BY a.UserId, a.DisplayName, a.UserRank

  UNION ALL

  -- Recent comments by the user (last 30 days), correlated subquery
  SELECT
    a.UserId,
    a.DisplayName,
    'RecentComments30d' AS MetricKey,
    COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.UserId = a.UserId AND c.CreationDate >= NOW() - INTERVAL '30 days'), 0) AS MetricValue,
    CONCAT_WS(' | ', a.DisplayName, 'recent_comments=', COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.UserId = a.UserId AND c.CreationDate >= NOW() - INTERVAL '30 days'), 0)) AS Detail,
    a.UserRank
  FROM ActiveUsers a

  UNION ALL

  -- Gold badges count (class = 1) per user
  SELECT
    a.UserId,
    a.DisplayName,
    'BadgesGold' AS MetricKey,
    COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = a.UserId AND b."Class" = 1), 0) AS MetricValue,
    CONCAT_WS(' | ', a.DisplayName, 'gold_badges=', COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = a.UserId AND b."Class" = 1), 0)) AS Detail,
    a.UserRank
  FROM ActiveUsers a
)
SELECT
  UserId,
  DisplayName,
  MetricKey,
  MetricValue,
  Detail,
  UserRank,
  ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY MetricValue DESC) AS RankPerUser
FROM AllMetrics
ORDER BY UserId, RankPerUser;