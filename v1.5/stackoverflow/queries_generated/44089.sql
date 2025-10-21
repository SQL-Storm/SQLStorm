-- {"query": "44089.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 204166, "output_tokens": 69604} 
SELECT p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, 
       (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
       (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
       (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
       (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 24) AS SuggestedEdits,
       (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinks,
       (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId) AS OwnerBadges
FROM Posts p
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 100;