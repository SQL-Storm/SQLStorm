-- {"query": "5790.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 650} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastEditorUserId,
    p.LastEditorDisplayName,
    p.CommentCount,
    p.FavoriteCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Body,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Votes v
    ON p.Id = v.PostId
  WHERE p.LastActivityDate >= NOW() - INTERVAL '30 days'
),
HotAggregates AS (
  SELECT
    rh.PostId,
    rh.PostTypeId,
    rh.Title,
    rh.Tags,
    rh.CreationDate,
    rh.LastActivityDate,
    rh.Score,
    rh.ViewCount,
    rh.OwnerUserId,
    rh.OwnerDisplayName,
    rh.LastEditorUserId,
    rh.LastEditorDisplayName,
    rh.CommentCount,
    rh.FavoriteCount,
    rh.AcceptedAnswerId,
    rh.ParentId,
    rh.Body,
    COUNT(*) OVER (PARTITION BY rh.PostTypeId) AS TypeCount,
    SUM(COALESCE(v.BountyAmount,0)) OVER (PARTITION BY rh.PostTypeId) AS TotalBounties
  FROM RecentHot rh
  LEFT JOIN Votes v
    ON rh.PostId = v.PostId
)
SELECT
  h.PostId,
  h.PostTypeId,
  pt.Name AS PostTypeName,
  h.Title,
  h.Tags,
  h.CreationDate,
  h.LastActivityDate,
  h.Score,
  h.ViewCount,
  u.Id AS OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  u.Location,
  COALESCE(o.LastEditorUserId, -1) AS LastEditorUserId,
  COALESCE(oe.DisplayName, h.LastEditorDisplayName) AS LastEditorDisplayName,
  h.CommentCount,
  h.FavoriteCount,
  h.AcceptedAnswerId,
  h.ParentId,
  h.Body,
  h.TotalBounties,
  h.TypeCount,
  bs.Name AS BadgeName,
  bt.Name AS TagName
FROM HotAggregates h
JOIN PostTypes pt ON h.PostTypeId = pt.Id
LEFT JOIN Users u ON h.OwnerUserId = u.Id
LEFT JOIN Users oe ON h.LastEditorUserId = oe.Id
LEFT JOIN Badges bs ON bs.UserId = u.Id AND bs.Class = 1
LEFT JOIN Tags t ON t.WikiPostId = h.PostId OR t.ExcerptPostId = h.PostId
LEFT JOIN (SELECT DISTINCT TagName FROM Tags) AS bt ON 1=1
WHERE h.rn <= 100
ORDER BY h.LastActivityDate DESC, h.Score DESC, h.ViewCount DESC
LIMIT 200;