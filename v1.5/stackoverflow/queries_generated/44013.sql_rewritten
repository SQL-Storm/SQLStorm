-- {"query": "44013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 29822, "output_tokens": 10367} 
SELECT p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Title, p.Tags, u.Id AS UserId, u.Reputation, u.DisplayName, u.LastAccessDate, b.Id AS BadgeId, b.Name AS BadgeName, b.Date AS BadgeDate, b.Class AS BadgeClass, b.TagBased AS BadgeTagBased, COALESCE(ph.Comment, '') AS PostHistoryComment, COALESCE(ph.Text, '') AS PostHistoryText, COALESCE(ph.CreationDate, p.CreationDate) AS PostHistoryCreationDate, ph.PostHistoryTypeId, COALESCE(ph.UserId, p.OwnerUserId) AS PostHistoryUserId, COALESCE(ph.UserDisplayName, p.OwnerDisplayName) AS PostHistoryUserDisplayName, COALESCE(c.Id, 0) AS CommentId, c.Score AS CommentScore, c.Text AS CommentText, c.CreationDate AS CommentCreationDate, c.UserDisplayName AS CommentUserDisplayName, c.UserId AS CommentUserId, pl.Id AS PostLinkId, pl.CreationDate AS PostLinkCreationDate, pl.RelatedPostId, pl.LinkTypeId, v.Id AS VoteId, v.VoteTypeId, v.UserId AS VoteUserId, v.CreationDate AS VoteCreationDate, v.BountyAmount
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
ORDER BY p.CreationDate DESC
LIMIT 100;