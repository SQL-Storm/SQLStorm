SELECT 
  p.Id AS PostId,
  p.PostTypeId,
  p.CreationDate,
  p.LastActivityDate,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  u.Id AS UserId,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate,
  COALESCE(b.Name, '') AS BadgeName,
  COALESCE(b.Date, DATE '0001-01-01') AS BadgeDate,
  COALESCE(b.Class, 0) AS BadgeClass,
  COALESCE(CASE WHEN b.TagBased IS TRUE THEN 1 WHEN b.TagBased IS FALSE THEN 0 ELSE NULL END, 0) AS BadgeTagBased,
  COALESCE(t.TagName, '') AS TagName,
  COALESCE(t.Count, 0) AS TagCount,
  COALESCE(t.ExcerptPostId, 0) AS TagExcerptPostId,
  COALESCE(t.WikiPostId, 0) AS TagWikiPostId,
  COALESCE(CASE WHEN t.IsModeratorOnly IS TRUE THEN 1 WHEN t.IsModeratorOnly IS FALSE THEN 0 ELSE NULL END, 0) AS TagIsModeratorOnly,
  COALESCE(CASE WHEN t.IsRequired IS TRUE THEN 1 WHEN t.IsRequired IS FALSE THEN 0 ELSE NULL END, 0) AS TagIsRequired,
  COALESCE(v.VoteTypeId, 0) AS VoteTypeId,
  COALESCE(v.BountyAmount, 0) AS VoteBonus,
  COALESCE(v.CreationDate, DATE '0001-01-01') AS VoteCreationDate,
  COALESCE(l.LinkTypeId, 0) AS LinkTypeId,
  COALESCE(l.CreationDate, DATE '0001-01-01') AS LinkCreationDate,
  COALESCE(ph.PostHistoryTypeId, 0) AS PostHistoryTypeId,
  COALESCE(ph.CreationDate, DATE '0001-01-01') AS PostHistoryCreationDate,
  COALESCE(ph.Comment, '') AS PostHistoryComment,
  COALESCE(ph.Text, '') AS PostHistoryText,
  COALESCE(c.Score, 0) AS CommentScore,
  COALESCE(c.CreationDate, DATE '0001-01-01') AS CommentCreationDate
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Tags t ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostLinks l ON p.Id = l.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.CreationDate >= DATE '2020-01-01'
  AND p.CreationDate <= DATE '2020-12-31'
ORDER BY p.CreationDate DESC
LIMIT 1000;