-- {"query": "26039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 643} 
WITH RankedPosts AS (
  SELECT 
    p.Id,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RowNum,
    DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS DenseRank
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1 AND p.Score > 0
),
TopUsers AS (
  SELECT 
    u.Id,
    u.DisplayName,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM 
    Users u
  LEFT JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    u.Id, u.DisplayName
),
PostHistorySummary AS (
  SELECT 
    ph.PostId,
    COUNT(DISTINCT ph.PostHistoryTypeId) AS HistoryCount,
    SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseCount,
    SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenCount
  FROM 
    PostHistory ph
  GROUP BY 
    ph.PostId
)
SELECT 
  p.Id,
  p.Score,
  p.ViewCount,
  p.Title,
  u.DisplayName AS OwnerDisplayName,
  tu.BadgeCount,
  tu.GoldBadges,
  tu.SilverBadges,
  tu.BronzeBadges,
  phs.HistoryCount,
  phs.CloseCount,
  phs.ReopenCount,
  rp.RowNum,
  rp.DenseRank,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
  (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 9) AS BountyAmount,
  (SELECT COUNT(DISTINCT t.TagName) FROM PostLinks pl JOIN Tags t ON pl.RelatedPostId = t.Id WHERE pl.PostId = p.Id) AS TagCount,
  (SELECT COUNT(DISTINCT pl.LinkTypeId) FROM PostLinks pl WHERE pl.PostId = p.Id) AS LinkTypeCount
FROM 
  Posts p
JOIN 
  RankedPosts rp ON p.Id = rp.Id
JOIN 
  Users u ON p.OwnerUserId = u.Id
JOIN 
  TopUsers tu ON u.Id = tu.Id
JOIN 
  PostHistorySummary phs ON p.Id = phs.PostId
WHERE 
  p.Score > 0 AND p.ViewCount > 0
  AND u.Reputation > 1000
  AND tu.BadgeCount > 5
  AND phs.HistoryCount > 2
ORDER BY 
  p.Score DESC, p.ViewCount DESC
LIMIT 100;