-- {"query": "59076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 993} 
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
    p.Tags,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as Downvotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCount,
    (SELECT STRING_AGG(b.Name, ', ') FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) as GoldBadges,
    (SELECT STRING_AGG(b.Name, ', ') FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) as SilverBadges,
    (SELECT STRING_AGG(b.Name, ', ') FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) as BronzeBadges,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 1) as TitleEdits,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 2) as BodyEdits,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 6) as TagEdits,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10) as ClosedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 11) as ReopenedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 12) as DeletedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 13) as UndeletedCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as DuplicateLinks,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) as LinkedPosts,
    (SELECT MIN(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10,11)) as FirstCloseReopen,
    (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10,11)) as LastCloseReopen,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) as BountyStarts,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 9) as BountyCloses,
    (SELECT MIN(v.CreationDate) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) as FirstBounty,
    (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 9) as LastBountyClose,
    (SELECT COUNT(DISTINCT ph.UserId) FROM PostHistory ph WHERE ph.PostId = p.Id) as EditorsCount,
    (SELECT COUNT(DISTINCT v.UserId) FROM Votes v WHERE v.PostId = p.Id AND v.PostTypeId IN (2,3)) as VotorsCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1
    AND p.CreationDate >= '2020-01-01'
    AND p.Score >= 100
    AND p.ViewCount >= 1000
    AND p.AnswerCount >= 5
    AND p.CommentCount >= 10
    AND (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10) > 0
    AND (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) > 0
    AND (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) >= 2
    AND (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) >= 5
ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 1000;