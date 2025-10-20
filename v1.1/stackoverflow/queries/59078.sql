SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerName,
    u.Reputation,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
        WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
        WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
    END AS PostType,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    COALESCE(p.CommentCount, 0) AS CommentCount,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
    SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)) AS TagsList,
    STRING_AGG(DISTINCT t.TagName, ', ') AS TagNames,
    STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames,
    STRING_AGG(DISTINCT CAST(v.VoteTypeId AS VARCHAR), ', ') AS VoteTypes,
    COUNT(DISTINCT c.Id) AS CommentCountDistinct,
    COUNT(DISTINCT ph.Id) AS HistoryCount,
    COUNT(DISTINCT pl.Id) AS LinkCount,
    MAX(ph.CreationDate) AS LastHistoryDate,
    MAX(c.CreationDate) AS LastCommentDate,
    MAX(u.LastAccessDate) AS UserLastAccessDate
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN (
    SELECT DISTINCT p2.Id AS PostId, tag_array.TagName
    FROM Posts p2
    CROSS JOIN LATERAL (
        SELECT REPLACE(REPLACE(p2.Tags, '<', ''), '>', '') AS TagsString
    ) ts
    CROSS JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(ts.TagsString, '><')) AS TagName
    ) tag_array
    WHERE p2.Tags IS NOT NULL AND p2.Tags <> ''
) tag ON tag.PostId = p.Id
LEFT JOIN Tags t ON tag.TagName = t.TagName
LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
WHERE p.CreationDate >= DATE '2020-01-01'
  AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
  AND p.Score > 10
  AND u.Reputation > 1000
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, 
    u.DisplayName, u.Reputation, p.PostTypeId, 
    p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Tags, 
    u.LastAccessDate
HAVING 
    COUNT(DISTINCT ph.Id) > 5
    AND COUNT(DISTINCT v.Id) > 3
    AND COUNT(DISTINCT c.Id) > 2
ORDER BY 
    p.Score DESC,
    p.ViewCount DESC,
    p.CreationDate DESC
LIMIT 1000;