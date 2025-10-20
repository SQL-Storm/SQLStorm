-- {"query": "336.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 17568} 
WITH
  w60 AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(CASE WHEN p.CreationDate > NOW() - INTERVAL '60 days' THEN p.Id END) AS Posts60,
      AVG(CASE WHEN p.CreationDate > NOW() - INTERVAL '60 days' THEN p.Score END) AS AvgScore60,
      MAX(CASE WHEN p.CreationDate > NOW() - INTERVAL '60 days' THEN p.LastActivityDate END) AS LastActive60,
      COUNT(CASE WHEN b.Id IS NOT NULL AND b.Class = 1 THEN 1 END) AS GoldBadges60,
      (SELECT p3.Title
       FROM Posts p3
       WHERE p3.OwnerUserId = u.Id
       ORDER BY COALESCE(p3.LastActivityDate, p3.CreationDate) DESC
       LIMIT 1) AS LastPostTitle60
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
  ),
  w180 AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(CASE WHEN p.CreationDate > NOW() - INTERVAL '180 days' THEN p.Id END) AS Posts180,
      AVG(CASE WHEN p.CreationDate > NOW() - INTERVAL '180 days' THEN p.Score END) AS AvgScore180,
      MAX(CASE WHEN p.CreationDate > NOW() - INTERVAL '180 days' THEN p.LastActivityDate END) AS LastActive180,
      COUNT(CASE WHEN b.Id IS NOT NULL AND b.Class = 1 THEN 1 END) AS GoldBadges180,
      (SELECT p3.Title
       FROM Posts p3
       WHERE p3.OwnerUserId = u.Id
       ORDER BY COALESCE(p3.LastActivityDate, p3.CreationDate) DESC
       LIMIT 1) AS LastPostTitle180
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
  ),
  combined AS (
    SELECT
      UserId,
      DisplayName,
      Reputation,
      Posts60 AS Posts,
      AvgScore60 AS AvgScore,
      GoldBadges60 AS GoldBadges,
      LastActive60 AS LastActive,
      LastPostTitle60 AS LastPostTitle,
      '60d' AS Window
    FROM w60
    UNION ALL
    SELECT
      UserId,
      DisplayName,
      Reputation,
      Posts180,
      AvgScore180,
      GoldBadges180,
      LastActive180,
      LastPostTitle180,
      '180d' AS Window
    FROM w180
  ),
  ranked AS (
    SELECT
      UserId,
      DisplayName,
      Reputation,
      Posts,
      AvgScore,
      GoldBadges,
      LastActive,
      LastPostTitle,
      Window,
      ROW_NUMBER() OVER (
        PARTITION BY UserId
        ORDER BY (Reputation * 0.1 + Posts * 2 + COALESCE(AvgScore, 0) * 5 + GoldBadges * 15) DESC
      ) AS rn
    FROM combined
  )
SELECT
  UserId,
  DisplayName,
  Reputation,
  Posts,
  AvgScore,
  GoldBadges,
  LastActive,
  LastPostTitle,
  Window
FROM ranked
WHERE rn = 1
ORDER BY Reputation DESC, Posts DESC
LIMIT 100;