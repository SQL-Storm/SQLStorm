-- {"query": "5192.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 537} 
WITH
RecentActivePosts AS (
  SELECT p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.LastActivityDate,
         p.Score, p.ViewCount, p.Tags,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.LastActivityDate IS NOT NULL
),
TopTagStats AS (
  SELECT
    t.TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews,
    MIN(p.CreationDate) AS FirstQuestion,
    MAX(p.LastActivityDate) AS MostRecentActivity
  FROM Posts p
  JOIN unnest(string_to_array(p.Tags, '><')) AS t(tag)
    ON true
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(p.Id) AS PostsCreated,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE u.AccountId IS NOT NULL
  GROUP BY u.Id, u.DisplayName
),
Combined AS (
  SELECT
    r.Id AS PostId,
    r.Title,
    r.CreationDate,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    r.Tags,
    u.UserId,
    u.DisplayName AS OwnerName,
    a.TotalViews AS OwnerTotalViews,
    a.PostsCreated
  FROM RecentActivePosts r
  LEFT JOIN UserActivity a ON a.UserId = r.OwnerUserId
  LEFT JOIN Users u ON u.Id = r.OwnerUserId
  WHERE r.rn = 1
)
SELECT
  c.PostId,
  c.Title,
  c.CreationDate,
  c.LastActivityDate,
  c.Score,
  c.ViewCount,
  c.Tags,
  c.OwnerName,
  c.TotalViews AS OwnerTotalViews,
  c.PostsCreated
FROM Combined c
LEFT JOIN TopTagStats tts ON tts.TagName IN (
  SELECT TRIM(both ' ' FROM tag) FROM unnest(string_to_array(c.Tags, '><')) AS tag
)
ORDER BY c.LastActivityDate DESC
LIMIT 100;