-- {"query": "59005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 790} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerDisplayName,
    u.Reputation,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) as VoteCount,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) as AnswerCount,
    (SELECT STRING_AGG(t.TagName, ', ') FROM (
        SELECT unnest(string_to_array(trim(trim(p.Tags, '<>'), '><'))::text) as TagName
    ) t) as TagsList,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) as GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) as SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) as BronzeBadges,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10,11,12,13)) as ModificationCount,
    (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id) as LastModificationDate,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as DuplicateCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 1) as LinkedFromCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) as FavoriteCount
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1 
    AND p.CreationDate >= '2022-01-01'
    AND p.Score >= 10
    AND p.ViewCount >= 100
    AND u.Reputation >= 1000
    AND (p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2)
    AND NOT EXISTS (
        SELECT 1 FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.PostHistoryTypeId = 12 
        AND ph.CreationDate >= '2022-01-01'
    )
    AND EXISTS (
        SELECT 1 FROM Comments c 
        WHERE c.PostId = p.Id 
        AND c.CreationDate >= '2022-01-01'
    )
    AND EXISTS (
        SELECT 1 FROM Votes v 
        WHERE v.PostId = p.Id 
        AND v.VoteTypeId IN (2,3)
        AND v.CreationDate >= '2022-01-01'
    )
    AND NOT EXISTS (
        SELECT 1 FROM Posts a 
        WHERE a.ParentId = p.Id 
        AND a.PostTypeId = 2 
        AND a.Score >= 100
        AND a.CreationDate >= '2022-01-01'
    )
    AND (SELECT COUNT(*) FROM PostHistory ph 
         WHERE ph.PostId = p.Id 
         AND ph.PostHistoryTypeId IN (1,2,3,4,5,6)
         AND ph.CreationDate >= '2022-01-01') >= 1
ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 1000;