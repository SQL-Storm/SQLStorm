SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerName,
    u.Reputation,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT v.Id) as VoteCount,
    COUNT(DISTINCT ph.Id) as HistoryCount,
    t.TagName as Tags,
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
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
    END as PostStatus,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as UpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as DownVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) as FavoriteCount,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN ph.Id END) as ModerationEvents,
    MAX(ph.CreationDate) as LastEditDate,
    COUNT(DISTINCT pl.Id) as LinkCount,
    COUNT(DISTINCT b.Id) as BadgeCount
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
LEFT JOIN (
    SELECT PostId, STRING_AGG(TagName, ', ') as TagName
    FROM (
        SELECT p2.Id as PostId,
               tag AS TagName
        FROM Posts p2,
             LATERAL (
                SELECT UNNEST(string_to_array(SUBSTRING(p2.Tags FROM 2 FOR LENGTH(p2.Tags) - 2), '><')) AS tag
             ) s
        WHERE p2.Tags IS NOT NULL AND p2.Tags <> ''
    ) tt
    GROUP BY PostId
) t ON p.Id = t.PostId
WHERE p.CreationDate >= DATE '2020-01-01'
    AND p.PostTypeId IN (1, 2)
    AND p.Score >= 0
    AND p.ViewCount >= 50
    AND (p.ClosedDate IS NULL OR p.ClosedDate >= DATE '2020-01-01')
    AND (p.CommunityOwnedDate IS NULL OR p.CommunityOwnedDate >= DATE '2020-01-01')
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, 
    u.DisplayName, u.Reputation, p.PostTypeId, p.AcceptedAnswerId, 
    p.ClosedDate, p.CommunityOwnedDate, t.TagName
HAVING 
    COUNT(DISTINCT c.Id) >= 2 
    OR COUNT(DISTINCT v.Id) >= 10
    OR COUNT(DISTINCT ph.Id) >= 5
ORDER BY 
    p.ViewCount DESC, 
    p.Score DESC,
    p.CreationDate DESC
LIMIT 1000;