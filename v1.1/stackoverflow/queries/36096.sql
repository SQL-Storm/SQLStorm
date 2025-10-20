SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.DisplayName,
  p.Tags,
  (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS ChildAnswerCount,
  (SELECT AVG(v2.BountyAmount) FROM Votes v2 WHERE v2.PostId = p.Id AND v2.VoteTypeId = 8) AS AvgBountyStartingAmount,
  (SELECT COUNT(*) FROM Votes v3 WHERE v3.PostId = p.Id AND v3.VoteTypeId = 2) AS UpVotes,
  (SELECT COUNT(*) FROM Votes v4 WHERE v4.PostId = p.Id AND v4.VoteTypeId = 3) AS DownVotes,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
  (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = p.Id) AS LastVoteDate,
  (SELECT pv.Name
     FROM PostHistory ph
     JOIN PostHistoryTypes pv ON ph.PostHistoryTypeId = pv.Id
     WHERE ph.PostId = p.Id AND pv.Name LIKE '%Closed%'
     ORDER BY ph.CreationDate DESC
     LIMIT 1) AS LastCloseReason
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1
  AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365 days'
GROUP BY
  p.Id,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  u.Reputation,
  u.CreationDate,
  u.DisplayName,
  p.Tags
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 100;