WITH
RecentActivePosts AS (
  SELECT p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.LastActivityDate,
         p.Score, p.ViewCount, p.Tags,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate IS NOT NULL
),
TopTagStats AS (
  SELECT
    tagvals.tag AS TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews,
    MIN(p.CreationDate) AS FirstQuestion,
    MAX(p.LastActivityDate) AS MostRecentActivity
  FROM Posts p,
       LATERAL (
         SELECT TRIM(t) AS tag
         FROM (SELECT UNNEST(STRING_TO_ARRAY(p.Tags, '><')) AS t) AS unnested
       ) AS tagvals
  GROUP BY tagvals.tag
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
    u.Id AS UserId,
    u.DisplayName AS OwnerName,
    a.TotalViews AS OwnerTotalViews,
    a.PostsCreated,
    r.rn
  FROM RecentActivePosts r
  LEFT JOIN UserActivity a ON a.UserId = r.OwnerUserId
  LEFT JOIN Users u ON u.Id = r.OwnerUserId
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
  c.OwnerTotalViews,
  c.PostsCreated
FROM Combined c
LEFT JOIN TopTagStats tts
  ON EXISTS (
    SELECT 1
    FROM (
      SELECT TRIM(t) AS tag
      FROM (SELECT UNNEST(STRING_TO_ARRAY(c.Tags, '><')) AS t) AS unnested
    ) AS t
    WHERE t.tag = tts.TagName
  )
WHERE c.rn = 1
ORDER BY c.LastActivityDate DESC
LIMIT 100;