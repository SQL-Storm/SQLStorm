-- {"query": "36048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 319} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.Tags,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  COUNT(DISTINCT v.Id) AS NetVotes,
  MAX(v.CreationDate) AS LastVoteDate,
  COUNT(DISTINCT c.Id) AS CommentCount,
  AVG(CASE WHEN v.VoteTypeId = 2 THEN 1.0 ELSE 0 END) AS UpvoteRatio,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN Comments c ON c.PostId = p.Id
WHERE p.PostTypeId = 1
  AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY
  p.Id,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.Tags,
  p.OwnerUserId,
  u.DisplayName
HAVING COUNT(DISTINCT c.Id) > 0
ORDER BY NetVotes DESC, p.CreationDate DESC
LIMIT 100;