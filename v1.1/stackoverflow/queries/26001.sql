WITH RankedPosts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.OwnerUserId, 
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RowNum,
    DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS DenseRank,
    LAG(p.Score, 1) OVER (ORDER BY p.Score DESC) AS PrevScore
  FROM Posts p
),
TagCounts AS (
  SELECT 
    t.TagName, 
    COUNT(*) AS Count
  FROM Tags t
  GROUP BY t.TagName
),
UserReputation AS (
  SELECT 
    u.Id, 
    SUM(b.Class) AS TotalBadges
  FROM Users u
  JOIN Badges b ON u.Id = b.UserId
  GROUP BY u.Id
)
SELECT 
  p.Id, 
  p.Score, 
  p.ViewCount, 
  p.OwnerUserId, 
  u.DisplayName, 
  u.Reputation, 
  ur.TotalBadges, 
  COALESCE(tc.Count, 0) AS TagCount,
  rp.RowNum, 
  rp.DenseRank, 
  rp.PrevScore,
  ph.PostHistoryTypeId, 
  ph.CreationDate AS PostHistoryDate,
  v.VoteTypeId, 
  v.CreationDate AS VoteDate,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS DownVotes,
  SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS Favorites,
  SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS CloseVotes,
  SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS ReopenVotes
FROM Posts p
JOIN RankedPosts rp ON p.Id = rp.Id
JOIN Users u ON p.OwnerUserId = u.Id
JOIN UserReputation ur ON u.Id = ur.Id
JOIN PostHistory ph ON p.Id = ph.PostId
JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN TagCounts tc ON t.TagName = tc.TagName
WHERE p.PostTypeId = 1
  AND p.Score > 0
  AND p.ViewCount > 0
  AND u.Reputation > 0
  AND ur.TotalBadges > 0
  AND ph.PostHistoryTypeId IN (10, 11)
  AND v.VoteTypeId IN (2, 3, 5)
GROUP BY
  p.Id,
  p.Score,
  p.ViewCount,
  p.OwnerUserId,
  u.DisplayName,
  u.Reputation,
  ur.TotalBadges,
  tc.Count,
  rp.RowNum,
  rp.DenseRank,
  rp.PrevScore,
  ph.PostHistoryTypeId,
  ph.CreationDate,
  v.VoteTypeId,
  v.CreationDate
ORDER BY p.Score DESC, p.ViewCount DESC, u.Reputation DESC;