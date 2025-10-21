-- {"query": "36077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 354} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.ViewCount,
  p.Score,
  p.CreationDate,
  p.LastActivityDate,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
  (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AnswerCount,
  (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id) AS AvgBounty,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,6,16)) AS EngagementScore,
  (SELECT STRING_AGG(CONCAT(ts.Name, ':', (CASE WHEN v.VoteTypeId IS NOT NULL THEN v.VoteTypeId ELSE 0 END)), '|')
     FROM Votes v
     JOIN VoteTypes ts ON v.VoteTypeId = ts.Id
     WHERE v.PostId = p.Id) AS VoteTypesSummary,
  CASE
    WHEN p.PostTypeId = 1 THEN 'Question'
    WHEN p.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostKind
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
WHERE
  p.CreationDate >= NOW() - INTERVAL '30 days'
  AND p.ViewCount > 0
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 100;