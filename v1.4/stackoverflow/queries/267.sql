-- {"query": "267.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 8614} 
WITH
LastActivity AS (
  SELECT OwnerUserId AS UserId,
         MAX(LastActivityDate) AS LastActivityDate,
         SUM(ViewCount) AS TotalViews,
         AVG(Score) AS AvgScore
  FROM Posts
  GROUP BY OwnerUserId
),
BadgeAgg AS (
  SELECT UserId, COUNT(*) AS BadgeCount, MAX(Date) AS LastBadgeDate
  FROM Badges
  GROUP BY UserId
),
TopPost AS (
  SELECT p.OwnerUserId AS UserId,
         p.Id AS PostId,
         p.Score,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
),
TopTag AS (
  SELECT p.OwnerUserId AS UserId, t.tag, COUNT(*) AS TagCount
  FROM Posts p
  CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(tag)
  GROUP BY p.OwnerUserId, t.tag
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(la.TotalViews, 0) AS TotalViews,
  COALESCE(la.AvgScore, 0) AS AvgPostScore,
  COALESCE(ba.BadgeCount, 0) AS BadgeCount,
  (SELECT tt.tag FROM TopTag tt WHERE tt.UserId = u.Id ORDER BY tt.TagCount DESC, tt.tag LIMIT 1) AS TopTag,
  (SELECT STRING_AGG(CONCAT('P', pt.PostId, ':', pt.Score), '; ')
     FROM TopPost pt WHERE pt.UserId = u.Id AND pt.rn <= 3) AS Top3Posts
FROM Users u
LEFT JOIN LastActivity la ON la.UserId = u.Id
LEFT JOIN BadgeAgg ba ON ba.UserId = u.Id

UNION ALL

SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(la.TotalViews, 0) AS TotalViews,
  COALESCE(la.AvgScore, 0) AS AvgPostScore,
  COALESCE(ba.BadgeCount, 0) AS BadgeCount,
  NULL AS TopTag,
  NULL AS Top3Posts
FROM Users u
LEFT JOIN LastActivity la ON la.UserId = u.Id
LEFT JOIN BadgeAgg ba ON ba.UserId = u.Id
WHERE u.Reputation > 100000
ORDER BY Reputation DESC
LIMIT 400;