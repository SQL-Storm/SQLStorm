SELECT p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation, 
       COUNT(DISTINCT c.Id) AS CommentCount, 
       COUNT(DISTINCT v.Id) AS VoteCount,
       STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
       STRING_AGG(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1,4) THEN ph.Text END, ' | ') AS TitleEdits,
       STRING_AGG(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (2,5) THEN ph.Text END, ' | ') AS BodyEdits,
       MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReason,
       MAX(CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.CreationDate END) AS DeletionDate,
       COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 35 THEN ph.Id END) AS MigrationCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN (
    SELECT p2.Id AS PostId, STRING_AGG(t.TagName, ', ') AS TagName
    FROM Posts p2
    JOIN Tags t ON p2.Tags LIKE '%' || t.TagName || '%'
    WHERE p2.PostTypeId = 1
    GROUP BY p2.Id
) t ON p.Id = t.PostId
WHERE p.PostTypeId = 1 
  AND p.CreationDate >= '2022-01-01'
  AND u.Reputation > 1000
  AND p.Score > 0
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT ph.Id) >= 5
   AND COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10,12,13) THEN ph.Id END) = 0
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 1000;