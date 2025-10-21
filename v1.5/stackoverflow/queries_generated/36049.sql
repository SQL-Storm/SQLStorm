-- {"query": "36049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 301} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
  COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
  COUNT(DISTINCT c.Id) AS CommentCount,
  STRING_AGG(t.Name, ',') AS Tags,
  ht.Name AS HistoryEvent
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN Comments c ON c.PostId = p.Id
LEFT JOIN LATERAL (
  SELECT pt.Name
  FROM PostHistory ph
  JOIN PostHistoryTypes pt ON ph.PostHistoryTypeId = pt.Id
  WHERE ph.PostId = p.Id
  ORDER BY ph.CreationDate DESC
  LIMIT 1
) AS ht ON true
LEFT JOIN UNNEST(string_to_array(p.Tags, '<>')) AS t ON true
GROUP BY
  p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId, u.DisplayName, ht.Name
ORDER BY
  p.CreationDate DESC
LIMIT 100;