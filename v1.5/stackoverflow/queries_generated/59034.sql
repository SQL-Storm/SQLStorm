-- {"query": "59034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 462} 
SELECT p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation, 
       COUNT(DISTINCT c.Id) as CommentCount, 
       COUNT(DISTINCT v.Id) as VoteCount,
       STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
       STRING_AGG(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1,4) THEN ph.Text END, ' | ') as TitleEdits,
       STRING_AGG(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (2,5) THEN ph.Text END, ' | ') as BodyEdits,
       MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) as CloseReason,
       MAX(CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.CreationDate END) as DeletionDate,
       COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 35 THEN ph.Id END) as MigrationCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN (
    SELECT PostId, STRING_AGG(TagName, ', ') as TagName
    FROM Posts p2
    JOIN Tags t ON p2.Tags LIKE '%' || t.TagName || '%'
    WHERE p2.PostTypeId = 1
    GROUP BY PostId
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