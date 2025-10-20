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
    p.Tags,
    STRING_AGG(DISTINCT t.TagName, ', ') as AllTags,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT v.Id) as VoteCount,
    MAX(v.CreationDate) as LastVoteDate,
    COUNT(DISTINCT ph.Id) as HistoryCount,
    MAX(ph.CreationDate) as LastHistoryDate,
    COUNT(DISTINCT pl.Id) as LinkCount,
    COUNT(DISTINCT b.Id) as BadgeCount,
    STRING_AGG(DISTINCT b.Name, ', ') as Badges,
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
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.ParentId IS NOT NULL THEN 'Answer'
        ELSE 'Question'
    END as PostStatus,
    COALESCE(p.AcceptedAnswerId, 0) as AcceptedAnswerId,
    COALESCE(p.ParentId, 0) as ParentId,
    COALESCE(p.FavoriteCount, 0) as FavoriteCount,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2) as AnswerCountRaw,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.PostTypeId = 1 AND p3.Tags LIKE '%' || p.Tags || '%') as RelatedQuestionCount,
    (SELECT COUNT(*) FROM Comments c2 WHERE c2.PostId = p.Id) as CommentCountRaw,
    (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = p.Id AND v2.VoteTypeId IN (2,3)) as UpDownVoteCount,
    (SELECT COUNT(*) FROM Votes v3 WHERE v3.PostId = p.Id AND v3.VoteTypeId = 5) as FavoriteCountRaw,
    (SELECT COUNT(*) FROM PostHistory ph2 WHERE ph2.PostId = p.Id AND ph2.PostHistoryTypeId IN (1,4,6,10,11,12,13,14,15,19,20,35,36)) as EditCount,
    (SELECT COUNT(*) FROM PostHistory ph3 WHERE ph3.PostId = p.Id AND ph3.PostHistoryTypeId IN (17,35,36)) as MigrationCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN (
    SELECT p4.Id as PostId, t.TagName
    FROM Posts p4,
         LATERAL (
             SELECT TRIM(BOTH '<>' FROM UNNEST(string_to_array(p4.Tags, '><'))) as TagName
         ) t
    WHERE t.TagName <> ''
) t ON p.Id = t.PostId
WHERE p.PostTypeId IN (1,2)
  AND p.CreationDate >= '2020-01-01'
  AND p.Score >= 0
  AND u.Reputation >= 100
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation, p.AnswerCount, p.CommentCount, p.Tags, p.PostTypeId, p.ClosedDate, p.CommunityOwnedDate, p.ParentId, p.FavoriteCount, p.AcceptedAnswerId
HAVING COUNT(DISTINCT c.Id) > 0
   OR COUNT(DISTINCT v.Id) > 0
   OR COUNT(DISTINCT ph.Id) > 0
ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 10000;