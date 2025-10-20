-- {"query": "44073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 167462, "output_tokens": 58028} 

SELECT p.Id, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, u.DisplayName, u.Reputation, u.AccountId, COUNT(v.Id) AS VoteCount, COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes, COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes, COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoritesCount, COUNT(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 END) AS ClosedPosts, COUNT(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 END) AS CommunityOwnedPosts, COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 1 END) AS PostActionCount, COUNT(CASE WHEN ph.PostHistoryTypeId = 14 THEN 1 END) AS PostLockedCount, COUNT(CASE WHEN ph.PostHistoryTypeId IN (19, 20) THEN 1 END) AS PostProtectionCount, COUNT(CASE WHEN pl.LinkTypeId = 3 THEN 1 END) AS DuplicatePostCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
GROUP BY p.Id, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, u.DisplayName, u.Reputation, u.AccountId
ORDER BY p.CreationDate DESC
LIMIT 1000;
