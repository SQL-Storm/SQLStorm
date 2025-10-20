-- {"query": "235.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 6188} 
WITH AllUserPosts AS (
  SELECT p.Id, p.OwnerUserId, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
),
TagUsage AS (
  SELECT a.OwnerUserId AS UserId,
         t.TagName,
         COUNT(*) AS TagCount
  FROM AllUserPosts a
  CROSS JOIN LATERAL unnest(string_to_array(substr(a.Tags, 2, length(a.Tags) - 2), '><')) AS t(TagName)
  GROUP BY a.OwnerUserId, t.TagName
),
TopTags AS (
  SELECT UserId,
         STRING_AGG(TagName, ', ' ORDER BY TagCount DESC) AS TopTags
  FROM (
    SELECT UserId, TagName, TagCount,
           ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCount DESC) AS rn
    FROM TagUsage
  ) s
  WHERE rn <= 3
  GROUP BY UserId
),
UserTotals AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         COALESCE(SUM(p.Score), 0) AS TotalScore_AllPosts,
         COALESCE(COUNT(p.Id), 0) AS PostCount_AllPosts,
         COALESCE(SUM(p.ViewCount), 0) AS TotalViews
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
RecentActivity AS (
  SELECT u.Id AS UserId,
         COALESCE(SUM(CASE WHEN p.CreationDate >= now() - interval '365 days' THEN 1 ELSE 0 END), 0) AS PostsLastYear
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  ut.PostCount_AllPosts,
  ut.TotalScore_AllPosts,
  ut.TotalViews,
  ra.PostsLastYear,
  COALESCE(b.TotalBadges, 0) AS BadgesTotal,
  tt.TopTags
FROM Users u
LEFT JOIN UserTotals ut ON ut.UserId = u.Id
LEFT JOIN (
  SELECT UserId, COUNT(*) AS TotalBadges
  FROM Badges
  GROUP BY UserId
) b ON b.UserId = u.Id
LEFT JOIN TopTags tt ON tt.UserId = u.Id
LEFT JOIN RecentActivity ra ON ra.UserId = u.Id
ORDER BY ut.TotalScore_AllPosts DESC NULLS LAST
LIMIT 100;