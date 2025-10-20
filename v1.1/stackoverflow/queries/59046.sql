SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerName,
    u.Reputation,
    COUNT(c.Id) AS CommentCount,
    COUNT(v.Id) AS VoteCount,
    COUNT(ph.Id) AS HistoryCount,
    COUNT(pl.Id) AS LinkCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
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
    END AS PostType,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.AnswerCount > 0 THEN 'Answered'
        ELSE 'Unanswered'
    END AS PostStatus,
    MAX(ph.CreationDate) AS LastActivity,
    EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)) / 86400 AS AgeInDays
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN (
    SELECT
        p2.Id AS PostId,
        TRIM(tagg) AS TagName
    FROM Posts p2,
    LATERAL (
        SELECT regexp_split_to_table(p2.Tags, '<>') AS tagg
    ) s
    WHERE p2.Tags IS NOT NULL AND p2.Tags <> ''
) t ON p.Id = t.PostId
WHERE p.CreationDate >= DATE '2023-01-01' 
    AND p.CreationDate <= DATE '2023-12-31'
    AND p.ViewCount > 100
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
    AND u.Reputation > 1000
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, 
    u.DisplayName, u.Reputation, p.PostTypeId, p.ClosedDate, 
    p.CommunityOwnedDate, p.AnswerCount
HAVING 
    COUNT(c.Id) > 5 
    AND COUNT(v.Id) > 10
    AND COUNT(ph.Id) > 2
ORDER BY 
    p.ViewCount DESC, 
    p.Score DESC,
    COUNT(v.Id) DESC,
    MAX(ph.CreationDate) DESC
LIMIT 10000;