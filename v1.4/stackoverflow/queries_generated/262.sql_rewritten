-- {"query": "262.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 13770} 
WITH
user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(u.Location, '') AS Location,
    MAX(p.LastActivityDate) AS LastActivityDate,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
badge_stats AS (
  SELECT
    UserId,
    MAX(Date) AS LastBadgeDate,
    SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount
  FROM Badges
  GROUP BY UserId
),
latest_q AS (
  SELECT p.OwnerUserId AS UserId,
         p.Id AS PostId,
         p.Score,
         p.LastActivityDate,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
latest_a AS (
  SELECT p.OwnerUserId AS UserId,
         p.Id AS PostId,
         p.Score,
         p.LastActivityDate,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 2
),
combined AS (
  SELECT UserId, PostId, Score, LastActivityDate
  FROM latest_q
  WHERE rn = 1
  UNION ALL
  SELECT UserId, PostId, Score, LastActivityDate
  FROM latest_a
  WHERE rn = 1
)
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.QuestionCount,
  ua.AnswerCount,
  COALESCE(bs.GoldBadgeCount, 0) AS GoldBadgeCount,
  bs.LastBadgeDate,
  ua.LastActivityDate,
  (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ua.UserId AND c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days') AS CommentsLast30Days,
  (ua.DisplayName || ' @' || COALESCE(NULLIF(ua.Location, ''), 'unknown')) AS ProfileLabel,
  COALESCE(array_length(string_to_array(substring(tp.Tags, 2, length(tp.Tags)-2), '><'), 1), 0) AS TopPostTagCount,
  COALESCE(c.Score, 0) AS TopPostScore,
  COALESCE(c.LastActivityDate, ua.LastActivityDate) AS TopPostActivityDate
FROM user_activity ua
LEFT JOIN badge_stats bs ON bs.UserId = ua.UserId
LEFT JOIN combined c ON c.UserId = ua.UserId
LEFT JOIN Posts tp ON tp.Id = c.PostId
ORDER BY ua.Reputation DESC, CommentsLast30Days DESC
LIMIT 100;