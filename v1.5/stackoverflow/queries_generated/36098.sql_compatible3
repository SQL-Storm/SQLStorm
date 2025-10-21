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
  p.AnswerCount,
  p.CommentCount,
  p.Tags,
  pc.Counts AS CommentTotalAcrossPosts,
  COALESCE(vt.VoteCount, 0) AS UpDownVoteCount,
  COALESCE(bd.BadgeTotal, 0) AS BadgeTotal,
  STRING_AGG(DISTINCT ct.CommunityTag, ',') AS TopTagCluster
FROM
  Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS Counts
    FROM Comments
    GROUP BY PostId
  ) pc ON pc.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCount
    FROM Votes
    WHERE VoteTypeId IN (2, 3)
    GROUP BY PostId
  ) vt ON vt.PostId = p.Id
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS BadgeTotal
    FROM Badges
    GROUP BY OwnerUserId
  ) bd ON bd.OwnerUserId = p.OwnerUserId
  LEFT JOIN (
    SELECT pt.Id AS PostTypeId, STRING_AGG(t.TagName, ',') AS CommunityTag
    FROM Posts pt
      JOIN Tags t ON POSITION(t.TagName IN pt.Tags) > 0
    GROUP BY pt.Id
  ) ct ON ct.PostTypeId = p.Id
WHERE
  p.PostTypeId IN (1, 2)
  AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365 days'
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
  p.AnswerCount,
  p.CommentCount,
  p.Tags,
  pc.Counts,
  vt.VoteCount,
  bd.BadgeTotal,
  ct.CommunityTag
ORDER BY
  p.Score DESC,
  vt.VoteCount DESC,
  p.ViewCount DESC
LIMIT 100;