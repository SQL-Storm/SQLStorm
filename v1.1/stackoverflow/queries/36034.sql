SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  COALESCE(a.CountAnswer, 0) AS AnswerCount,
  COALESCE(v.UpVoteCount, 0) AS UpVotes,
  COALESCE(v.DownVoteCount, 0) AS DownVotes,
  p.Tags,
  COALESCE(la.LastActivityDate, p.LastActivityDate) AS LastActivityDate,
  p.FavoriteCount,
  p.ParentId,
  p.AcceptedAnswerId,
  bh.LastHistoryType,
  bh.HistoryEventCount,
  cl.Name AS CloseReason
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN (
  SELECT
    Parent.Id AS PostId,
    COUNT(*) AS CountAnswer
  FROM Posts Parent
  WHERE Parent.PostTypeId = 2
  GROUP BY Parent.Id
) a ON p.Id = a.PostId
LEFT JOIN (
  SELECT
    PostId,
    SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
  FROM Votes
  GROUP BY PostId
) v ON p.Id = v.PostId
LEFT JOIN (
  SELECT
    Id AS PostId,
    MAX(LastEditDate) AS LastActivityDate
  FROM Posts
  GROUP BY Id
) la ON p.Id = la.PostId
LEFT JOIN (
  SELECT
    ph.PostId,
    MAX(ph.CreationDate) AS LastHistoryDate,
    MAX(ph.Id) AS LastHistoryId,
    MAX(CASE WHEN ph.PostHistoryTypeId = 52 THEN 1 ELSE 0 END) AS LastHistoryType,
    COUNT(*) AS HistoryEventCount
  FROM PostHistory ph
  GROUP BY ph.PostId
) bh ON p.Id = bh.PostId
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN CloseReasonTypes cl ON ph.Comment LIKE '%' || CAST(cl.Id AS VARCHAR(100)) || '%'
WHERE p.PostTypeId IN (1, 2)
  AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365' DAY)
GROUP BY
  p.Id,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  u.DisplayName,
  u.Reputation,
  a.CountAnswer,
  v.UpVoteCount,
  v.DownVoteCount,
  p.Tags,
  la.LastActivityDate,
  p.LastActivityDate,
  p.FavoriteCount,
  p.ParentId,
  p.AcceptedAnswerId,
  bh.LastHistoryType,
  bh.HistoryEventCount,
  cl.Name
ORDER BY p.ViewCount DESC, p.Score DESC
LIMIT 100;