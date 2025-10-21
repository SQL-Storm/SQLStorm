-- {"query": "36038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 396} 
SELECT
  p.Id AS PostId,
  p.PostTypeId,
  p.Title,
  p.Body,
  p.Score,
  p.ViewCount,
  p.CreationDate,
  p.LastActivityDate,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  COUNT(DISTINCT c.Id) AS CommentCount,
  COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
  COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteSumOverTime,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteSumOverTime,
  MAX(CASE WHEN t.Name = 'Closed' THEN ph.CreationDate END) AS LastClosedDate,
  COUNT(DISTINCT bl.Id) AS LinkCount
FROM
  Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
  LEFT JOIN PostLinks bl ON bl.PostId = p.Id
  LEFT JOIN PostHistoryTypes t ON ph.PostHistoryTypeId = t.Id
WHERE
  p.CreationDate >= NOW() - INTERVAL '30 days'
GROUP BY
  p.Id, p.PostTypeId, p.Title, p.Body, p.Score, p.ViewCount, p.CreationDate, p.LastActivityDate, p.OwnerUserId, u.DisplayName
ORDER BY
  p.CreationDate DESC
LIMIT 100;