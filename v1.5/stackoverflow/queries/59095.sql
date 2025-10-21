-- {"query": "59095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 604} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerName,
    u.Reputation,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as DownVotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCount,
    (SELECT STRING_AGG(b.Name, ', ') FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 1) as GoldBadges,
    (SELECT STRING_AGG(b.Name, ', ') FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 2) as SilverBadges,
    (SELECT STRING_AGG(b.Name, ', ') FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 3) as BronzeBadges,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1,2,3,4,5,6)) as EditCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10) as CloseCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 12) as DeleteCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 13) as UndeleteCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as DuplicateLinkCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) as LinkCount,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2) as AnswerCountIncludingDeleted
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1 
    AND p.CreationDate >= '2023-01-01 00:00:00'
    AND p.Score >= 100
    AND p.ViewCount >= 1000
    AND u.Reputation >= 10000
    AND EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2)
    AND EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id)
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 1000;