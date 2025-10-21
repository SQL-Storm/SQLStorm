-- {"query": "59098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 753} 
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
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as TotalComments,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as Downvotes,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 1) as GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 2) as SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 3) as BronzeBadges,
    (SELECT STRING_AGG(t.TagName, ', ') FROM (
        SELECT DISTINCT unnest(string_to_array(trim(p.Tags, '<>'), '><')) as TagName
    ) t WHERE t.TagName IS NOT NULL AND t.TagName != '') as TagList,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
        WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
        WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
        ELSE 'Unknown'
    END as PostType,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1, 2, 3)) as EditCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11, 12, 13)) as StatusChangeCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as DuplicateCount,
    (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id) as LastEditDate,
    (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.PostId = p.Id) as LastCommentDate,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 24) as SuggestedEdits,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) as AvgBountyAmount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.CreationDate >= '2022-01-01'
    AND p.CreationDate < '2023-01-01'
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
    AND p.Score >= 0
    AND p.ViewCount >= 100
    AND p.AnswerCount >= 1
    AND p.CommentCount >= 0
ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 10000;