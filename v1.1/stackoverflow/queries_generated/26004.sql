-- {"query": "26004.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 727} 

WITH TopUsers AS (
  SELECT u.Id, u.DisplayName, u.Reputation, 
         ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RowNum
  FROM Users u
  WHERE u.Reputation > 10000
),
TopPosts AS (
  SELECT p.Id, p.Score, p.ViewCount, p.Tags, 
         ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RowNum
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Score > 100
),
TopBadges AS (
  SELECT b.UserId, b.Name, b.Date, 
         ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS RowNum
  FROM Badges b
  WHERE b.Class = 1
),
PostHistoryCTE AS (
  SELECT ph.PostId, ph.PostHistoryTypeId, ph.CreationDate, 
         LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PrevDate
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10, 11)
)
SELECT 
  u.Id, u.DisplayName, u.Reputation, 
  p.Id AS PostId, p.Score, p.ViewCount, p.Tags, 
  b.Name AS BadgeName, b.Date AS BadgeDate,
  ph.CreationDate AS PostHistoryDate, ph.PrevDate AS PrevPostHistoryDate,
  CASE 
    WHEN ph.PostHistoryTypeId = 10 THEN 'Closed'
    WHEN ph.PostHistoryTypeId = 11 THEN 'Reopened'
  END AS PostHistoryType,
  ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS RowNum
FROM Users u
JOIN TopUsers tu ON u.Id = tu.Id
JOIN Posts p ON u.Id = p.OwnerUserId
JOIN PostLinks pl ON p.Id = pl.PostId
JOIN PostHistoryCTE ph ON p.Id = ph.PostId
JOIN TopBadges b ON u.Id = b.UserId
WHERE p.Score > 100 AND u.Reputation > 10000
  AND ph.PostHistoryTypeId IN (10, 11)
  AND b.Class = 1
  AND p.Id NOT IN (SELECT PostId FROM PostHistory WHERE PostHistoryTypeId = 12)
UNION ALL
SELECT 
  u.Id, u.DisplayName, u.Reputation, 
  p.Id AS PostId, p.Score, p.ViewCount, p.Tags, 
  b.Name AS BadgeName, b.Date AS BadgeDate,
  ph.CreationDate AS PostHistoryDate, ph.PrevDate AS PrevPostHistoryDate,
  CASE 
    WHEN ph.PostHistoryTypeId = 10 THEN 'Closed'
    WHEN ph.PostHistoryTypeId = 11 THEN 'Reopened'
  END AS PostHistoryType,
  ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS RowNum
FROM Users u
JOIN TopUsers tu ON u.Id = tu.Id
JOIN Posts p ON u.Id = p.OwnerUserId
JOIN PostLinks pl ON p.Id = pl.PostId
JOIN PostHistoryCTE ph ON p.Id = ph.PostId
JOIN TopBadges b ON u.Id = b.UserId
WHERE p.Score > 100 AND u.Reputation > 10000
  AND ph.PostHistoryTypeId IN (10, 11)
  AND b.Class = 1
  AND p.Id IN (SELECT PostId FROM PostHistory WHERE PostHistoryTypeId = 12);
