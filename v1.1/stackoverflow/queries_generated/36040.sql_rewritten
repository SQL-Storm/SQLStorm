-- {"query": "36040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 440} 
SELECT
  p.Id AS PostId,
  p.PostTypeId,
  p.Title,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  p.LastActivityDate,
  p.Tags,
  COUNT(v.Id) AS TotalVotes,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
  SUM(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END) AS Deletions,
  SUM(CASE WHEN vt.Name = '' THEN 0 ELSE 1 END) AS UniqueVoteTypes,
  MAX(v.CreationDate) FILTER (WHERE v.VoteTypeId = 2) AS LastUpVoteDate,
  COUNT(CASE WHEN c.Id IS NOT NULL THEN 1 END) AS CommentCount,
  STRING_AGG(CASE WHEN v.VoteTypeId = 2 THEN 'Up' WHEN v.VoteTypeId = 3 THEN 'Down' END, ',') AS VoteTypesSnapshot
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Users vu ON v.UserId = vu.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN (SELECT Id, Name FROM VoteTypes) vt ON v.VoteTypeId = vt.Id
WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
  AND p.PostTypeId IN (1, 2)
GROUP BY
  p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.ViewCount,
  p.OwnerUserId, u.DisplayName, p.LastActivityDate, p.Tags;