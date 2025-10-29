-- {"query": "5077.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 981}
WITH
RecentActive AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC('week', p.LastActivityDate)
                       ORDER BY p.LastActivityDate DESC) AS wk_rank
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
),
TopTags AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    b.Name AS BadgeName,
    b.Class AS BadgeClass,
    b.Date AS BadgeDate,
    t.TagName
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT DISTINCT TagName FROM Tags
  ) t ON 1=1
  WHERE u.Reputation > 1000
),
CorrelatedSub AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.Tags,
    ra.OwnerUserId,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.Score,
    ra.ViewCount,
    ra.AnswerCount,
    ra.CommentCount,
    ra.FavoriteCount,
    ra.PostTypeId,
    ra.wk_rank,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = ra.PostId AND v.VoteTypeId = 9) AS AvgBounty
  FROM RecentActive ra
  WHERE ra.wk_rank = 1
),
Joined AS (
  SELECT
    c.PostId,
    c.Title,
    c.Tags,
    c.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.AccountId,
    c.LastActivityDate,
    c.Score,
    c.ViewCount,
    c.AnswerCount,
    c.CommentCount,
    c.FavoriteCount,
    c.PostTypeId,
    c.AvgBounty,
    d.DisplayName AS LastEditorName,
    c.wk_rank
  FROM CorrelatedSub c
  LEFT JOIN Users u ON u.Id = c.OwnerUserId
  LEFT JOIN Users d ON d.Id = (
    SELECT p2.LastEditorUserId FROM Posts p2 WHERE p2.Id = c.PostId
  )
  LEFT JOIN PostLinks pl ON pl.PostId = c.PostId
  LEFT JOIN Tags t ON t.WikiPostId = c.PostId OR t.ExcerptPostId = c.PostId
),
Agg AS (
  SELECT
    PostId,
    Title,
    OwnerUserId,
    OwnerDisplayName,
    Reputation,
    LastActivityDate,
    PostTypeId,
    AVG(AvgBounty) OVER () AS OverallAvgBounty,
    SUM(ViewCount) OVER () AS TotalViews,
    SUM(AnswerCount) OVER () AS TotalAnswers
  FROM Joined
)
SELECT
  p.PostTypeId,
  pt.Name AS PostTypeName,
  p.Id AS PostId,
  p.Title,
  p.Tags,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  p.LastActivityDate,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  p.LastEditDate,
  p.ContentLicense,
  COALESCE(b.Name, '') AS LastEditorBadge,
  COALESCE(b.Class, 0) AS LastEditorBadgeClass,
  b.Date AS LastEditorBadgeDate,
  COALESCE(a.OverallAvgBounty, 0) AS OverallAvgBounty,
  COALESCE(a.TotalViews, 0) AS TotalViewsBenchmark,
  COALESCE(a.TotalAnswers, 0) AS TotalAnswersBenchmark
FROM Posts p
JOIN PostTypes pt ON pt.Id = p.PostTypeId
LEFT JOIN Agg a ON a.PostId = p.Id
LEFT JOIN Users u ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN (SELECT 1 AS dummy) x ON 1=1
WHERE p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY)
  AND (p.Tags LIKE '%<sql>%' OR p.Title LIKE '%benchmark%')
ORDER BY p.LastActivityDate DESC
LIMIT 100;