-- {"query": "59062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 857} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerName,
    u.Reputation,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as Downvotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1, 4, 5, 6)) as EditCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 1) as GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 2) as SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 3) as BronzeBadges,
    (SELECT ARRAY_AGG(DISTINCT t.TagName) FROM (
        SELECT UNNEST(string_to_array(p.Tags, '><')) as TagName
    ) t WHERE t.TagName IS NOT NULL AND t.TagName != '') as TagsArray,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        ELSE 'Other'
    END as PostType,
    CASE 
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Yes'
        ELSE 'No'
    END as HasAcceptedAnswer,
    (SELECT COUNT(*) FROM Posts ap WHERE ap.ParentId = p.Id AND ap.PostTypeId = 2) as AnswerCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as DuplicateCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10) as ClosedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 11) as ReopenedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 12) as DeletedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 13) as UndeletedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 14) as LockedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 15) as UnlockedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 19) as ProtectedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 20) as UnprotectedCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 24) as EditAppliedCount
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.CreationDate >= '2022-01-01' 
    AND p.CreationDate < '2023-01-01'
    AND p.PostTypeId IN (1, 2)
    AND (p.Score > 5 OR p.ViewCount > 100)
    AND u.Reputation > 1000
    AND (p.Tags IS NOT NULL AND p.Tags != '')
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 1000;