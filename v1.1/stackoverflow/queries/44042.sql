-- {"query": "44042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 96348, "output_tokens": 35059} 
SELECT p.Id AS PostId, p.Title, p.CreationDate, p.ViewCount, p.Score, p.AnswerCount, p.CommentCount, p.FavoriteCount, u.DisplayName AS OwnerDisplayName, u.Reputation AS OwnerReputation, u.AccountId AS OwnerAccountId, 
       (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId) AS OwnerBadgeCount,
       (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
       (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
       (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
       (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateCount,
       (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS LinkedCount,
       (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11, 14, 15)) AS ClosedReopenedLockedUnlockedCount,
       (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (12, 13)) AS DeletedUndeletedCount,
       (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) AS BountyStartCount,
       (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 9) AS BountyCloseCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
ORDER BY p.ViewCount DESC
LIMIT 100;