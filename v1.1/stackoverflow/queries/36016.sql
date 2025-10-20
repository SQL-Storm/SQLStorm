-- {"query": "36016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 317} 
SELECT
  p.Id AS PostId,
  p.PostTypeId,
  p.Title,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  p.Tags,
  COUNT(DISTINCT c.Id) AS CommentCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
  MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate END) AS LastUpVoteDate,
  MAX(p.LastEditDate) AS LastEditDate,
  MAX(p.LastActivityDate) AS LastActivityDate
FROM
  Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
WHERE
  p.PostTypeId = 1 -- only questions
  AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '1 year'
  AND p.ViewCount > 0
GROUP BY
  p.Id, p.PostTypeId, p.Title, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId, u.DisplayName, p.Tags
ORDER BY
  p.Score DESC,
  p.ViewCount DESC
LIMIT 100;