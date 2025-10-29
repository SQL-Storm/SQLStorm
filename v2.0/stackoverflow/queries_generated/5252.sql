-- {"query": "5252.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 849} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.IsActive IS NULL OR p.IsActive <> 0
),
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM Posts p
  CROSS APPLY (SELECT value AS TagName
               FROM string_split(p.Tags, '><') ) AS t
  GROUP BY t.TagName
),
Correlation AS (
  SELECT
    p1.PostId,
    p1.Title AS PostTitle,
    p1.CreationDate AS PostDate,
    p1.Score,
    p1.ViewCount,
    p1.OwnerUserId,
    p2.Id AS RelatedPostId,
    p2.Title AS RelatedTitle,
    p2.ViewCount AS RelatedViews,
    p2.Score AS RelatedScore
  FROM RecentHot p1
  LEFT JOIN PostLinks pl ON pl.PostId = p1.PostId
  LEFT JOIN Posts p2 ON p2.Id = pl.RelatedPostId
  WHERE pl.LinkTypeId IN (1,3)
),
WindowStats AS (
  SELECT
    c.PostId,
    c.PostTitle,
    c.PostDate,
    c.Score,
    c.ViewCount,
    c.OwnerUserId,
    c.RelatedPostId,
    c.RelatedTitle,
    c.RelatedViews,
    c.RelatedScore,
    COUNT(*) OVER (PARTITION BY c.PostId) AS LinkCount,
    AVG(NULLIF(c.RelatedScore, 0)) OVER (PARTITION BY c.PostId) AS AvgRelatedScore
  FROM Correlation c
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    b.Count AS BadgeCount,
    b.Class AS BadgeClass,
    b.Name AS BadgeName,
    b.Date AS BadgeDate
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
),
TemporalFlags AS (
  SELECT
    u.UserId,
    CASE
      WHEN DATEDIFF(day, u.LastAccessDate, GETDATE()) <= 7 THEN 1
      WHEN DATEDIFF(day, u.LastAccessDate, GETDATE()) <= 30 THEN 2
      ELSE 3
    END AS ActiveWindow
  FROM Users u
)
SELECT
  rp.PostId,
  rp.PostTitle,
  rp.PostDate,
  rp.Score AS PostScore,
  rp.ViewCount AS PostViews,
  rp.OwnerUserId,
  rp.RelatedPostId,
  rp.RelatedTitle,
  rp.RelatedViews AS RelatedViews,
  rp.RelatedScore AS RelatedScore,
  ws.LinkCount,
  ws.AvgRelatedScore,
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.CreationDate AS UserCreated,
  ua.LastAccessDate AS UserLastActive,
  ua.Views AS UserViews,
  ua.UpVotes,
  ua.DownVotes,
  ua.AccountId,
  ua.BadgeCount,
  ua.BadgeClass,
  ua.BadgeName,
  ua.BadgeDate,
  tf.ActiveWindow
FROM WindowStats ws
JOIN UserActivity ua ON ua.UserId = (
  SELECT TOP 1 OwnerUserId
  FROM Posts p
  WHERE p.Id = ws.PostId
)
JOIN TemporalFlags tf ON tf.UserId = ua.UserId
ORDER BY ws.LinkCount DESC, rp.ViewCount DESC
LIMIT 100;