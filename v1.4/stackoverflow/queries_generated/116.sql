-- {"query": "116.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1673} 
WITH
ActiveUsers AS (
  SELECT Id AS UserId, DisplayName, Reputation, CreationDate, LastAccessDate, Location
  FROM Users
  WHERE LastAccessDate > now() - interval '1 year'
),
UserStats AS (
  SELECT a.UserId,
         COUNT(p.Id) AS PostCount,
         AVG(p.Score) AS AvgScore,
         MAX(p.LastActivityDate) AS LastActivity
  FROM ActiveUsers a
  LEFT JOIN Posts p ON p.OwnerUserId = a.UserId
  GROUP BY a.UserId
),
TopPosts AS (
  SELECT p.Id AS PostId,
         p.OwnerUserId,
         p.Title,
         p.Score,
         p.ViewCount,
         p.LastActivityDate,
         p.Tags,
         ROW_NUMBER() OVER (
           PARTITION BY p.OwnerUserId
           ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST
         ) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
Top3 AS (
  SELECT tp.PostId,
         tp.OwnerUserId,
         tp.Title,
         tp.Score,
         tp.ViewCount,
         tp.LastActivityDate,
         tp.Tags
  FROM TopPosts tp
  WHERE tp.rn <= 3
)
SELECT
  u.UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(us.PostCount, 0) AS PostCount,
  COALESCE(us.AvgScore, 0.0) AS AvgScore,
  us.LastActivity,
  t.PostId,
  t.Title,
  t.Score,
  t.ViewCount,
  t.LastActivityDate,
  COALESCE(array_to_string(string_to_array(substr(t.Tags, 2, length(t.Tags) - 2), '><'), ','), '') AS Tags
FROM ActiveUsers u
LEFT JOIN UserStats us ON us.UserId = u.UserId
LEFT JOIN Top3 t ON t.OwnerUserId = u.UserId AND t.rn = 1
LEFT JOIN Badges b ON b.UserId = u.UserId
ORDER BY u.Reputation DESC, us.LastActivity DESC NULLS LAST
LIMIT 100;