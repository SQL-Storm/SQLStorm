-- {"query": "59043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 721} 
SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT bh.Id) AS HistoryCount,
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
    END AS PostType,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.ParentId IS NOT NULL THEN 'Answer'
        ELSE 'Question'
    END AS PostStatus,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
    MAX(bh.CreationDate) AS LastEditDate,
    MAX(p.LastActivityDate) AS LastActivityDate,
    STRING_AGG(DISTINCT CONCAT(u2.DisplayName, ' (', v.VoteTypeId, ')'), ', ') AS VoteDetails
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory bh ON p.Id = bh.PostId
LEFT JOIN (
    SELECT PostId, TagName 
    FROM Posts p
    JOIN (
        SELECT Id, unnest(string_to_array(trim(trim(Tags, '<>'), '><'))::text[]) AS TagName
        FROM Posts
        WHERE Tags IS NOT NULL AND Tags != ''
    ) tags ON p.Id = tags.Id
) t ON p.Id = t.PostId
LEFT JOIN Users u2 ON v.UserId = u2.Id
WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= '2023-01-01'
    AND p.CreationDate < '2024-01-01'
    AND p.Score >= 0
    AND u.Reputation > 100
GROUP BY 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.CreationDate, 
    u.DisplayName, 
    u.Reputation, 
    p.PostTypeId, 
    p.ClosedDate, 
    p.CommunityOwnedDate, 
    p.ParentId, 
    p.AnswerCount, 
    p.FavoriteCount, 
    p.LastActivityDate
HAVING 
    COUNT(DISTINCT c.Id) > 0
    OR COUNT(DISTINCT v.Id) > 0
    OR COUNT(DISTINCT bh.Id) > 0
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC,
    MAX(bh.CreationDate) DESC
LIMIT 10000;