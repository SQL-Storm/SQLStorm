-- {"query": "36090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 398} 
SELECT
  p.Id AS PostId,
  p.PostTypeId,
  p.Title,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes,
  COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS Downvotes,
  MAX(CASE WHEN ht.Id IS NOT NULL THEN ht.Name END) AS LastPostHistoryType,
  MAX(ph.CreationDate) AS LastActivityDate,
  COUNT(DISTINCT c.Id) AS CommentCount,
  ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE p.PostTypeId = 1) AS TagsUsed
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN PostHistoryTypes ht ON ph.PostHistoryTypeId = ht.Id
LEFT JOIN Comments c ON c.PostId = p.Id
LEFT JOIN LATERAL (
  SELECT
    tg.TagName
  FROM Tags tg
  JOIN Posts t ON t.Id = p.Id
  WHERE tg.Id = t.Id -- placeholder join path for tag extraction
  LIMIT 0
) t ON true
WHERE p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '30 days'
  AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
GROUP BY
  p.Id,
  p.PostTypeId,
  p.Title,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  u.DisplayName
ORDER BY
  p.Score DESC,
  LastActivityDate DESC
LIMIT 100;