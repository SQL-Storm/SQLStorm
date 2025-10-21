SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.Score,
  p.ViewCount,
  p.CreationDate,
  p.LastActivityDate,
  p.OwnerUserId,
  u.Reputation,
  u.DisplayName,
  COALESCE(vs.UpVotes, 0) AS UpVotesToday,
  COALESCE(vs.DownVotes, 0) AS DownVotesToday,
  COALESCE(cmt.CommentCount, 0) AS CommentCountToday,
  COALESCE(h.RevisionCount, 0) AS RevisionCountToday,
  (COALESCE(vs.UpVotes, 0) - COALESCE(vs.DownVotes, 0)) AS NetVoteDeltaToday,
  (COALESCE(cmt.CommentCount, 0) + COALESCE(h.RevisionCount, 0)) AS ActivityScoreToday
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN (
  SELECT PostId,
         SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE v.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 day'
  GROUP BY PostId
) AS vs ON p.Id = vs.PostId
LEFT JOIN (
  SELECT PostId,
         COUNT(*) AS CommentCount
  FROM Comments
  WHERE CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 day'
  GROUP BY PostId
) AS cmt ON p.Id = cmt.PostId
LEFT JOIN (
  SELECT PostId,
         COUNT(*) AS RevisionCount
  FROM PostHistory
  WHERE CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 day'
  GROUP BY PostId
) AS h ON p.Id = h.PostId
WHERE p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '7 day'
ORDER BY ActivityScoreToday DESC, NetVoteDeltaToday DESC
LIMIT 100;