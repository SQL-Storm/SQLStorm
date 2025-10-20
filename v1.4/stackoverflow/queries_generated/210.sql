-- {"query": "210.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 7268} 
WITH
UserStats AS (
  SELECT u.Id,
         COUNT(p.Id) AS PostCount,
         AVG(p.Score) AS AvgPostScore,
         SUM(p.ViewCount) AS TotalViews
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
BadgeStats AS (
  SELECT UserId,
         SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
         SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
         SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges
  GROUP BY UserId
),
TagUsage AS (
  SELECT p.OwnerUserId AS UserId,
         tagName,
         COUNT(*) AS TagCount
  FROM Posts p
  CROSS JOIN LATERAL unnest(string_to_array(coalesce(substring(p.Tags, 2, length(p.Tags) - 2), ''), '><')) AS tagName
  WHERE tagName <> ''
  GROUP BY p.OwnerUserId, tagName
),
TopTag AS (
  SELECT UserId, TagName, TagCount,
         ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCount DESC, TagName) AS rn
  FROM TagUsage
),
RecentBounties AS (
  SELECT UserId, SUM(BountyAmount) AS BountyThis30
  FROM Votes
  WHERE CreationDate >= (CURRENT_DATE - INTERVAL '30 days')
  GROUP BY UserId
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COALESCE(us.PostCount, 0) AS PostCount,
  COALESCE(us.AvgPostScore, 0.0) AS AvgPostScore,
  COALESCE(us.TotalViews, 0) AS TotalViews,
  COALESCE(bs.GoldBadges, 0) AS GoldBadges,
  COALESCE(bs.SilverBadges, 0) AS SilverBadges,
  COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
  COALESCE(rb.BountyThis30, 0) AS BountyThis30,
  (SELECT TagName FROM TopTag tt WHERE tt.UserId = u.Id AND tt.rn = 1) AS TopTag,
  (SELECT TagName FROM TopTag tt WHERE tt.UserId = u.Id AND tt.rn = 2) AS SecondTopTag,
  (SELECT TagName FROM TopTag tt WHERE tt.UserId = u.Id AND tt.rn = 3) AS ThirdTopTag,
  (COALESCE(us.TotalViews, 0) * 0.2 + COALESCE(us.PostCount, 0) * 5.0 + COALESCE(bs.GoldBadges, 0) * 10.0) AS EngagementScore
FROM Users u
LEFT JOIN UserStats us ON us.Id = u.Id
LEFT JOIN BadgeStats bs ON bs.UserId = u.Id
LEFT JOIN RecentBounties rb ON rb.UserId = u.Id
ORDER BY EngagementScore DESC, u.Reputation DESC
LIMIT 100;