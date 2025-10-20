SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  p.LastActivityDate,
  pc.Score AS LatestCommentScore,
  COUNT(DISTINCT c.Id) AS CommentCount,
  COUNT(DISTINCT v.Id) AS VoteCount,
  MAX(CASE WHEN v.VoteTypeId = (SELECT vt.Id FROM VoteTypes vt WHERE vt.Name = 'UpMod') THEN 1 ELSE 0 END) AS HasUpvoters,
  MAX(CASE WHEN v.VoteTypeId = (SELECT vt.Id FROM VoteTypes vt WHERE vt.Name = 'AcceptedByOriginator') THEN 1 ELSE 0 END) AS IsAnswered
FROM
  Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN (
    -- find latest comment for the same post
    SELECT c2.PostId, c2.Score
    FROM Comments c2
    JOIN (
      SELECT PostId, MAX(CreationDate) AS max_cd
      FROM Comments
      GROUP BY PostId
    ) m ON c2.PostId = m.PostId AND c2.CreationDate = m.max_cd
  ) pc ON pc.PostId = p.Id
WHERE
  p.PostTypeId IN (1, 2)
  AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
  AND p.ViewCount > 0
GROUP BY
  p.Id,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  u.DisplayName,
  p.LastActivityDate,
  pc.Score
ORDER BY
  p.Score DESC,
  p.ViewCount DESC
LIMIT 100;