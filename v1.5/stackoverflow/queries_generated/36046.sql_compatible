SELECT
  p.Id AS PostId,
  p.PostTypeId,
  p.Title,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.Tags,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  COUNT(v.Id) AS TotalVotes,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
  COUNT(c.Id) AS CommentCount,
  MAX(CASE WHEN c.CreationDate IS NOT NULL THEN c.CreationDate END) AS LastCommentDate,
  SUM(CASE WHEN br.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
  SUM(CASE WHEN br.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
  SUM(CASE WHEN br.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
FROM
  Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Badges br ON br.UserId = p.OwnerUserId
GROUP BY
  p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId, u.DisplayName
HAVING
  p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
ORDER BY
  p.Score DESC, p.ViewCount DESC
LIMIT 100;