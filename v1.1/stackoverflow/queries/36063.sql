SELECT
  p.Id AS PostId,
  p.PostTypeId,
  p.Title,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  p.Tags,
  ARRAY_AGG(DISTINCT cl.Name) AS CloseReasons,
  MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate END) AS LastUpvoteDate,
  MAX(CASE WHEN v.VoteTypeId = 2 THEN u2.DisplayName END) AS LastUpvoter,
  COUNT(DISTINCT a.Id) AS AnswerCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
  SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVoteCount
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN Users u2 ON v.UserId = u2.Id
LEFT JOIN (SELECT Id, Name FROM CloseReasonTypes) cl ON CAST(ph.Comment AS VARCHAR(400)) LIKE '%' || cl.Name || '%'
LEFT JOIN (SELECT Id, PostId, MAX(CreationDate) AS LastVoteDate FROM Votes GROUP BY PostId, Id) lv ON lv.PostId = p.Id
LEFT JOIN Posts a ON a.ParentId = p.Id
WHERE p.ParentId IS NULL
  AND p.PostTypeId IN (1, 2)
  AND p.CreationDate >= TIMESTAMP '2020-01-01'
GROUP BY
  p.Id,
  p.PostTypeId,
  p.Title,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.OwnerUserId,
  u.DisplayName,
  p.Tags
ORDER BY p.CreationDate DESC
LIMIT 100;