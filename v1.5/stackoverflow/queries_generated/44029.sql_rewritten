-- {"query": "44029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 66526, "output_tokens": 25564} 
SELECT 
  p.Title, 
  p.Tags, 
  p.OwnerUserId, 
  u.DisplayName AS OwnerDisplayName, 
  p.CreationDate, 
  p.LastEditDate, 
  p.Score, 
  p.ViewCount, 
  p.AnswerCount, 
  p.FavoriteCount, 
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
  (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id) AS PostHistoryCount,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id) AS PostLinkCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1
ORDER BY p.Score DESC
LIMIT 100;