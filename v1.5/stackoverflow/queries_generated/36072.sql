-- {"query": "36072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 370} 
SELECT
  p.Id AS PostId,
  p.PostTypeId,
  p.Title,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  p.LastEditDate,
  p.Tags,
  COUNT(DISTINCT c.Id) AS CommentCount,
  COUNT(DISTINCT v.Id) AS VoteCount,
  AVG(v2.BountyAmount) FILTER (WHERE v2.BountyAmount IS NOT NULL) AS AvgBountyIfAny,
  up.DisplayName AS LastEditorDisplayName,
  u.Reputation,
  b.Name AS BadgeName,
  AVG(DATE_PART('day', NOW() - p.CreationDate)) OVER () AS AvgAgeDays
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON c.PostId = p.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN Votes v2 ON v2.PostId = p.Id AND v2.VoteTypeId = 8
LEFT JOIN Users up ON p.LastEditorUserId = up.Id
LEFT JOIN Badges b ON b.UserId = u.Id AND b.Class = 1
WHERE p.PostTypeId = 1
  AND p.CreationDate >= NOW() - INTERVAL '1 year'
GROUP BY
  p.Id,
  p.PostTypeId,
  p.Title,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.OwnerUserId,
  u.DisplayName,
  p.LastEditDate,
  p.Tags,
  up.DisplayName,
  u.Reputation,
  b.Name
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 100;