-- {"query": "36026.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 524} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.Body,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  p.AcceptedAnswerId,
  p.CommentCount,
  p.Tags,
  CAST(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - p.CreationDate)) / 3600 AS INTEGER) AS HoursSinceCreation,
  COALESCE(vs.UpVotes, 0) AS UpVotesToday,
  COALESCE(vs.DownVotes, 0) AS DownVotesToday,
  COALESCE(b.TotalBadges, 0) AS TotalBadgesForOwner,
  COALESCE(h.EditCount, 0) AS EditsCount,
  ht.Name AS LastPostHistoryType
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN (
  SELECT PostId, COUNT(*) AS UpVotes, 0 AS DownVotes
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE vt.Name = 'UpMod'
  GROUP BY PostId
) AS vs ON p.Id = vs.PostId
LEFT JOIN (
  SELECT PostId, 0 AS UpVotes, COUNT(*) AS DownVotes
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE vt.Name = 'DownMod'
  GROUP BY PostId
) AS vd ON p.Id = vd.PostId
LEFT JOIN (
  SELECT OwnerUserId, COUNT(*) AS TotalBadges
  FROM Badges
  GROUP BY OwnerUserId
) b ON p.OwnerUserId = b.OwnerUserId
LEFT JOIN (
  SELECT PostId, COUNT(*) AS EditCount
  FROM PostHistory
  WHERE PostHistoryTypeId = 5 -- Edit Body
     OR PostHistoryTypeId = 4 -- Edit Title
     OR PostHistoryTypeId = 6 -- Edit Tags
  GROUP BY PostId
) h ON p.Id = h.PostId
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN PostHistoryTypes ht ON ph.PostHistoryTypeId = ht.Id
WHERE p.PostTypeId = 1 -- Questions
  AND p.CreationDate >= NOW() - INTERVAL '30 days'
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 100;