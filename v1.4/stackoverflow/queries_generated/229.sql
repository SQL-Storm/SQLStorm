-- {"query": "229.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 9772} 
WITH
Active AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    MAX(p.LastActivityDate) AS LastActivityDate,
    COALESCE(SUM(p.Score), 0) AS TotalPostScore,
    COALESCE(SUM(p.ViewCount), 0) AS TotalPostViews,
    COALESCE(AVG(p.Score), 0) AS AvgPostScore,
    COALESCE(COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1), 0) AS QuestionCount,
    COALESCE(b.BadgeCount, 0) AS BadgeCount,
    b.LastBadgeDate,
    t.TopTags,
    1 AS Source
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN BadgeInfo b ON b.UserId = u.Id
  LEFT JOIN TopTagsPerUser t ON t.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, b.BadgeCount, b.LastBadgeDate, t.TopTags
),
Inactive AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    NULL AS LastActivityDate,
    0 AS TotalPostScore,
    0 AS TotalPostViews,
    0 AS AvgPostScore,
    0 AS QuestionCount,
    0 AS BadgeCount,
    NULL AS LastBadgeDate,
    NULL AS TopTags,
    2 AS Source
  FROM Users u
  WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
),
BadgeInfo AS (
  SELECT UserId, COUNT(*) AS BadgeCount, MAX(Date) AS LastBadgeDate
  FROM Badges
  GROUP BY UserId
),
TopTagsPerUser AS (
  SELECT
    u.Id AS UserId,
    (
      SELECT array_agg(tagname)
      FROM (
        SELECT t.tagname, COUNT(*) AS ct
        FROM Posts p
        CROSS JOIN LATERAL unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(tagname)
        WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
        GROUP BY t.tagname
        ORDER BY ct DESC
        LIMIT 3
      ) s
    ) AS TopTags
  FROM Users u
),
Unified AS (
  SELECT * FROM Active
  UNION ALL
  SELECT * FROM Inactive
)
SELECT
  UserId,
  DisplayName,
  Reputation,
  Location,
  LastActivityDate,
  TotalPostScore,
  TotalPostViews,
  AvgPostScore,
  QuestionCount,
  BadgeCount,
  LastBadgeDate,
  TopTags,
  Source
FROM Unified
ORDER BY Source, UserId
LIMIT 200;