-- {"query": "59086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 753} 
SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    p.AnswerCount,
    p.CommentCount,
    p.Tags,
    STRING_AGG(DISTINCT t.TagName, ', ') AS TagList,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT ph.Id) AS HistoryCount,
    MAX(ph.CreationDate) AS LastEditDate,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
        WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
        WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
    END AS PostTypeName,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.ParentId IS NOT NULL THEN 'Answer'
        ELSE 'Question'
    END AS PostStatus,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) AS FavoriteCount,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END), 0) AS TotalBounty,
    STRING_AGG(DISTINCT CONCAT(u2.DisplayName, ' (', u2.Reputation, ')'), ', ') AS TopContributors,
    COUNT(DISTINCT pl.Id) AS LinkCount,
    STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames,
    MAX(b.Date) AS LatestBadgeDate
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN Users u2 ON v.UserId = u2.Id
LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
WHERE 
    p.CreationDate >= '2022-01-01' 
    AND p.PostTypeId IN (1, 2)
    AND (p.ViewCount > 1000 OR p.Score > 10)
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation, p.AnswerCount, p.CommentCount, p.Tags, p.PostTypeId, p.ClosedDate, p.CommunityOwnedDate, p.ParentId
HAVING 
    COUNT(DISTINCT v.Id) > 5 
    OR COUNT(DISTINCT c.Id) > 10
ORDER BY 
    p.ViewCount DESC, p.Score DESC
LIMIT 10000;