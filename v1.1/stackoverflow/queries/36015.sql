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
  SELECT v.PostId,
         SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE v.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1' DAY
  GROUP BY v.PostId
) AS vs ON p.Id = vs.PostId
LEFT JOIN (
  SELECT PostId,
         COUNT(*) AS CommentCount
  FROM Comments
  WHERE CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1' DAY
  GROUP BY PostId
) AS cmt ON p.Id = cmt.PostId
LEFT JOIN (
  SELECT PostId,
         COUNT(*) AS RevisionCount
  FROM PostHistory
  WHERE CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1' DAY
  GROUP BY PostId
) AS h ON p.Id = h.PostId
WHERE p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '7' DAY
GROUP BY
  p.Id,
  p.Title,
  p.PostTypeId,
  p.Score,
  p.ViewCount,
  p.CreationDate,
  p.LastActivityDate,
  p.OwnerUserId,
  u.Reputation,
  u.DisplayName,
  vs.UpVotes,
  vs.DownVotes,
  cmt.CommentCount,
  h.RevisionCount
ORDER BY ActivityScoreToday DESC, NetVoteDeltaToday DESC
LIMIT 100;