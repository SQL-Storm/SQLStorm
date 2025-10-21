-- {"query": "384.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 22128} 
WITH
RecentPosts AS (
  SELECT p.Id AS PostId,
         p.OwnerUserId,
         p.OwnerDisplayName,
         p.PostTypeId,
         p.Score,
         p.ViewCount,
         p.CreationDate,
         p.Title,
         p.Tags,
         COALESCE(b.BadgeCount, 0) AS BadgeCount,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS ScoreRank
  FROM Posts p
  LEFT JOIN (
     SELECT UserId, COUNT(*) AS BadgeCount
     FROM Badges
     GROUP BY UserId
  ) b ON b.UserId = p.OwnerUserId
  WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '365 days'
),
TagInfo AS (
  SELECT rp.PostId,
         t.TagName
  FROM RecentPosts rp
  CROSS JOIN LATERAL unnest(string_to_array(substring(rp.Tags, 2, length(rp.Tags) - 2), '><')) AS t(TagName)
),
TagPopularity AS (
  SELECT ti.TagName,
         COUNT(*) AS PostCount,
         SUM(p.ViewCount) AS TotalViews
  FROM TagInfo ti
  JOIN Posts p ON p.Id = ti.PostId
  GROUP BY ti.TagName
)
SELECT
  'Posts' AS Source,
  rp.OwnerUserId AS UserId,
  COALESCE((SELECT DisplayName FROM Users u WHERE u.Id = rp.OwnerUserId), rp.OwnerDisplayName) AS UserName,
  COALESCE((SELECT Reputation FROM Users u WHERE u.Id = rp.OwnerUserId), 0) AS Reputation,
  1 AS PostCount,
  rp.Score AS ScoreSum,
  rp.ViewCount AS ViewSum,
  rp.Title AS Label,
  (rp.CommentCount::text || '|' || rp.ScoreRank::text) AS Extra
FROM RecentPosts rp
UNION ALL
SELECT
  'Tags' AS Source,
  NULL AS UserId,
  NULL AS UserName,
  NULL AS Reputation,
  t.PostCount,
  NULL AS ScoreSum,
  t.TotalViews,
  'Tag: ' || t.TagName AS Label,
  NULL::text AS Extra
FROM TagPopularity t
ORDER BY Source, Label;