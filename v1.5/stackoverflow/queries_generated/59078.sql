-- {"query": "59078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 743} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerName,
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
    END as PostType,
    COALESCE(p.AnswerCount, 0) as AnswerCount,
    COALESCE(p.CommentCount, 0) as CommentCount,
    COALESCE(p.FavoriteCount, 0) as FavoriteCount,
    SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) as TagsList,
    STRING_AGG(t.TagName, ', ') as TagNames,
    STRING_AGG(b.Name, ', ') as BadgeNames,
    STRING_AGG(v.VoteTypeId, ', ') as VoteTypes,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT ph.Id) as HistoryCount,
    COUNT(DISTINCT pl.Id) as LinkCount,
    MAX(ph.CreationDate) as LastHistoryDate,
    MAX(c.CreationDate) as LastCommentDate,
    MAX(u.LastAccessDate) as UserLastAccessDate
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN (
    SELECT DISTINCT PostId, TagName 
    FROM Posts p2 
    JOIN (
        SELECT 
            CAST(SUBSTRING(Tags, 2, LENGTH(Tags) - 2) AS TEXT) as TagsString
        FROM Posts 
        WHERE Tags IS NOT NULL AND Tags != ''
    ) t ON t.TagsString IS NOT NULL
    JOIN (
        SELECT unnest(string_to_array(replace(replace(t.TagsString, '<', ''), '>', ''), '><')) as TagName
    ) tag_array ON tag_array.TagName != ''
    JOIN Tags tg ON tg.TagName = tag_array.TagName
) tag JOIN Tags t ON tag.TagName = t.TagName
LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
WHERE p.CreationDate >= '2020-01-01' 
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
    AND p.Score > 10
    AND u.Reputation > 1000
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, 
    u.DisplayName, u.Reputation, p.PostTypeId, 
    p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Tags
HAVING 
    COUNT(DISTINCT ph.Id) > 5
    AND COUNT(DISTINCT v.Id) > 3
    AND COUNT(DISTINCT c.Id) > 2
ORDER BY 
    p.Score DESC,
    p.ViewCount DESC,
    p.CreationDate DESC
LIMIT 1000;