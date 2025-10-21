SELECT 
  p.Id AS PostId, 
  p.PostTypeId, 
  p.OwnerUserId, 
  p.CreationDate, 
  p.Score, 
  p.ViewCount, 
  p.AnswerCount, 
  p.FavoriteCount, 
  p.ContentLicense, 
  COUNT(ph.Id) AS PostHistoryCount, 
  COUNT(pl.Id) AS PostLinkCount, 
  COUNT(v.Id) AS VoteCount, 
  COUNT(c.Id) AS CommentCount
FROM Posts p
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
GROUP BY
  p.Id,
  p.PostTypeId,
  p.OwnerUserId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.FavoriteCount,
  p.ContentLicense
ORDER BY PostHistoryCount DESC, PostLinkCount DESC, VoteCount DESC, CommentCount DESC
LIMIT 100;