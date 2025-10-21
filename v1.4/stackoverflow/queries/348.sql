-- {"query": "348.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 12879} 
WITH
  user_post_stats AS (
    SELECT p.OwnerUserId AS UserId,
           COUNT(*) AS PostCountAll,
           AVG(p.Score) AS AvgPostScore,
           MAX(p.LastActivityDate) AS LastPostDate
    FROM Posts p
    GROUP BY p.OwnerUserId
  ),
  user_post_comments AS (
    SELECT p.OwnerUserId AS UserId,
           COUNT(c.Id) AS CommentCount
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    GROUP BY p.OwnerUserId
  ),
  user_base AS (
    SELECT
      u.Id AS UserId,
      COALESCE(u.DisplayName, 'Unknown') AS DisplayName,
      u.Reputation,
      COALESCE(ups.PostCountAll, 0) AS PostCountAll,
      COALESCE(ups.AvgPostScore, 0) AS AvgPostScore,
      COALESCE(ups.LastPostDate, u.CreationDate) AS LastPostDate,
      COALESCE(uc.CommentCount, 0) AS CommentCount,
      CASE WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) THEN TRUE ELSE FALSE END AS HasGoldBadge,
      CASE WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.LastActivityDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days')) THEN TRUE ELSE FALSE END AS RecentlyActive30d,
      CONCAT('User:', COALESCE(u.DisplayName, 'Unknown'), ' | Rep=', u.Reputation, ' | Posts=', COALESCE(ups.PostCountAll, 0)) AS ProfileSummary
    FROM Users u
    LEFT JOIN user_post_stats ups ON ups.UserId = u.Id
    LEFT JOIN user_post_comments uc ON uc.UserId = u.Id
  ),
  ranked AS (
    SELECT
      UserId,
      DisplayName,
      Reputation,
      PostCountAll,
      AvgPostScore,
      LastPostDate,
      CommentCount,
      HasGoldBadge,
      RecentlyActive30d,
      ProfileSummary,
      ROW_NUMBER() OVER (ORDER BY PostCountAll DESC, AvgPostScore DESC, LastPostDate DESC) AS ActivityRank
    FROM user_base
  )
SELECT *
FROM (
  SELECT *
  FROM ranked
  WHERE PostCountAll > 0
  UNION ALL
  SELECT *
  FROM ranked
  WHERE PostCountAll = 0
) t
ORDER BY ActivityRank;