-- {"query": "36100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 426} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  p.LastActivityDate,
  p.Tags,
  COUNT(DISTINCT v.Id) AS TotalVotes,
  COUNT(DISTINCT c.Id) AS TotalComments,
  MAX(CASE WHEN vt.Id = 1 THEN 1 ELSE 0 END) AS HasAccepted,
  SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS NetUpDown,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
  AVG(CASE WHEN v.VoteTypeId IN (2,3) THEN v.BountyAmount ELSE NULL END) AS AvgVoteAmount,
  COUNT(DISTINCT ph.Id) AS RevisionCount,
  MAX(ph.CreationDate) AS LastRevisionDate
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
LEFT JOIN Comments c ON c.PostId = p.Id
WHERE
  p.CreationDate >= NOW() - INTERVAL '180 days'
  AND p.PostTypeId IN (1,2)
  AND (p.Tags IS NOT NULL OR p.Tags <> '')
GROUP BY
  p.Id, p.Title, p.PostTypeId, p.CreationDate, p.ViewCount, p.Score,
  p.OwnerUserId, u.DisplayName, p.LastActivityDate, p.Tags
ORDER BY
  NetUpDown DESC, p.Score DESC, p.ViewCount DESC
LIMIT 100;