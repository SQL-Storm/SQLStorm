-- {"query": "5085.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1014} 
WITH
-- a dense ranking of posts by activity with window functions
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.Tags,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.LastActivityDate DESC, p.Score DESC, p.ViewCount DESC
    ) AS rn
  FROM Posts p
  WHERE p.LastActivityDate IS NOT NULL
),
-- correlated subquery: compute aggregate stats per user for their posts
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS TotalPosts,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS AvgPostScore,
    (SELECT MAX(p.LastActivityDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastActive
  FROM Users u
),
-- aggregate counts across post types with a left join to include users with no posts
TypeBreakdown AS (
  SELECT
    pt.Id AS PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(p.Id) AS PostCount,
    SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) AS PositiveScore,
    SUM(CASE WHEN p.ViewCount > 1000 THEN 1 ELSE 0 END) AS HighViewPosts
  FROM PostTypes pt
  LEFT JOIN Posts p ON p.PostTypeId = pt.Id
  GROUP BY pt.Id, pt.Name
),
-- generate a complex predicate set on posts to exercise NULL handling and expressions
ComplexFilter AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    CASE
      WHEN p.Score IS NULL THEN 0
      WHEN p.Score < 0 THEN -ABS(p.Score)
      ELSE p.Score
    END AS NormalizedScore,
    CASE
      WHEN p.Tags IS NULL THEN 'untagged'
      ELSE TRIM(p.Tags)
    END AS CleanTags,
    CASE
      WHEN p.Body IS NULL THEN CAST('' AS VARCHAR(1000))
      WHEN LENGTH(p.Body) > 1000 THEN SUBSTRING(p.Body, 1, 1000)
      ELSE p.Body
    END AS Snippet
  FROM Posts p
  WHERE (p.PostTypeId = 1 OR p.PostTypeId = 2) -- focus on questions/answers
    AND (p.LastActivityDate IS NOT NULL)
    AND (p.ViewCount IS NULL OR p.ViewCount >= 0)
),
-- a set-operation: union of recent and popular posts
RecentOrPopular AS (
  (SELECT PostId, PostTypeId, LastActivityDate AS ActivityDate FROM RecentActivity WHERE rn <= 50)
  UNION ALL
  (SELECT p.Id AS PostId, p.PostTypeId, p.LastActivityDate AS ActivityDate
   FROM Posts p
   WHERE p.ViewCount >= 10000)
),
-- windowed ranking across authors by combined activity
AuthorActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    ROW_NUMBER() OVER (ORDER BY COALESCE(u.Reputation,0) DESC, COUNT(p.Id) OVER (PARTITION BY u.Id) DESC) AS Rank
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
)
SELECT
  r.PostId,
  r.Title AS PostTitle,
  t.PostTypeName,
  r.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  r.LastActivityDate,
  r.Score,
  r.ViewCount,
  c.Snippet AS BodySnippet,
  c.CleanTags,
  t2.PostCount AS TypePostCount,
  b.BadgeCount
FROM
  RecentOrPopular r
  LEFT JOIN Posts p ON p.Id = r.PostId
  LEFT JOIN PostTypes t ON t.Id = r.PostTypeId
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN ComplexFilter c ON c.Id = p.Id
  LEFT JOIN TypeBreakdown t2 ON t2.PostTypeId = r.PostTypeId
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS BadgeCount
    FROM Badges
    GROUP BY OwnerUserId
  ) b ON b.OwnerUserId = p.OwnerUserId
WHERE
  r.ActivityDate >= DATEADD(day, -30, CURRENT_DATE)
ORDER BY
  r.ActivityDate DESC,
  r.Score DESC
LIMIT 200;