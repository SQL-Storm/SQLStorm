-- {"query": "26012.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 591} 

WITH RankedPosts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.OwnerUserId, 
    p.AcceptedAnswerId, 
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS RowNum,
    LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PrevScore,
    LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS NextScore
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL
),
TopUsers AS (
  SELECT 
    u.Id, 
    u.Reputation, 
    COUNT(DISTINCT b.Name) AS BadgeCount
  FROM 
    Users u
  LEFT JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    u.Id, u.Reputation
  HAVING 
    COUNT(DISTINCT b.Name) > 10
),
PostHistoryCTE AS (
  SELECT 
    ph.PostId, 
    ph.PostHistoryTypeId, 
    ph.CreationDate, 
    ph.UserId, 
    ph.Comment, 
    ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS RowNum
  FROM 
    PostHistory ph
  WHERE 
    ph.PostHistoryTypeId IN (10, 11)
)
SELECT 
  rp.Id, 
  rp.Score, 
  rp.ViewCount, 
  rp.OwnerUserId, 
  tu.Reputation, 
  tu.BadgeCount, 
  ph.CreationDate AS CloseDate, 
  ph.Comment AS CloseReason, 
  rp.NextScore - rp.PrevScore AS ScoreDiff, 
  CASE 
    WHEN rp.RowNum = 1 THEN 'Top'
    WHEN rp.RowNum = 2 THEN 'Second'
    ELSE 'Other'
  END AS Rank,
  STRING_AGG(DISTINCT t.TagName, ', ') AS Tags
FROM 
  RankedPosts rp
JOIN 
  TopUsers tu ON rp.OwnerUserId = tu.Id
LEFT JOIN 
  PostHistoryCTE ph ON rp.Id = ph.PostId AND ph.RowNum = 1
LEFT JOIN 
  PostTags pt ON rp.Id = pt.PostId
LEFT JOIN 
  Tags t ON pt.TagId = t.Id
GROUP BY 
  rp.Id, rp.Score, rp.ViewCount, rp.OwnerUserId, tu.Reputation, tu.BadgeCount, ph.CreationDate, ph.Comment, rp.NextScore, rp.PrevScore, rp.RowNum
HAVING 
  rp.Score > 100 AND tu.Reputation > 10000
ORDER BY 
  rp.Score DESC;
