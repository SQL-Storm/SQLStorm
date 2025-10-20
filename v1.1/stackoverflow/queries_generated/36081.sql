-- {"query": "36081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 330} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS Downvotes,
  (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id) AS AnswerCount,
  (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) AS AverageBounty,
  (SELECT MAX(clr.Date) FROM PostHistory ph JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
     WHERE ph.PostId = p.Id AND pht.Name ILIKE '%Closed%') AS LastClosedDate,
  CASE
    WHEN p.LastEditDate IS NULL THEN p.CreationDate
    ELSE p.LastEditDate
  END AS LastActivityDate
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1
  AND p.CreationDate >= NOW() - INTERVAL '1 year'
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 100;