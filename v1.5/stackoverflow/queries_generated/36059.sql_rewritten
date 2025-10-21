-- {"query": "36059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 307} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.Tags,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  COUNT(DISTINCT v.Id) AS VoteCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
  COUNT(DISTINCT c.Id) AS CommentCount,
  ARRAY_AGG(DISTINCT ll.RelatedPostId) FILTER (WHERE ll.RelatedPostId IS NOT NULL) AS LinkedPostIds,
  MAX(pt.Name) AS PostType
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN Comments c ON c.PostId = p.Id
LEFT JOIN PostLinks ll ON ll.PostId = p.Id
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
GROUP BY
  p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId, u.DisplayName, pt.Name
ORDER BY
  p.Score DESC,
  p.ViewCount DESC
LIMIT 100;