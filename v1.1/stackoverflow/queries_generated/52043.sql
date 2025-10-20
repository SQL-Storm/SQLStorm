-- {"query": "52043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 347} 
SELECT p.Id, p.Title, p.Score, p.ViewCount,
       (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCount,
       (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as UpVotes,
       (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as DownVotes,
       (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 3) as DuplicateCount,
       (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as IsDuplicate,
       u.DisplayName, u.Reputation,
       (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) as BadgeCount,
       ARRAY(SELECT tag FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag WHERE tag IS NOT NULL) as TagArray,
       (SELECT AVG(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)) as AvgEditDate
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN (SELECT ParentId, COUNT(*) as AnswerCount FROM Posts WHERE PostTypeId = 2 GROUP BY ParentId) a ON p.Id = a.ParentId
WHERE p.PostTypeId = 1 AND p.Score > 10
ORDER BY p.Score DESC, p.ViewCount DESC, a.AnswerCount DESC
LIMIT 100;