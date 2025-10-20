-- {"query": "59041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 697} 
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
    COUNT(DISTINCT bh.Id) as HistoryCount,
    STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
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
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
        ELSE 'Open'
    END as PostStatus,
    MAX(v.CreationDate) as LatestVoteDate,
    MAX(bh.CreationDate) as LatestHistoryDate,
    MAX(c.CreationDate) as LatestCommentDate,
    p.AnswerCount,
    p.FavoriteCount,
    p.CommentCount as OriginalCommentCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory bh ON p.Id = bh.PostId
LEFT JOIN (
    SELECT Id, UNNEST(string_to_array(SUBSTRING(Tags, 2, LENGTH(Tags)-2), '><')) as TagName
    FROM Posts
    WHERE Tags IS NOT NULL AND Tags != ''
) t ON p.Id = t.Id
WHERE 
    p.CreationDate >= '2020-01-01' 
    AND p.CreationDate <= '2023-12-31'
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
    AND u.Reputation > 1000
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
    p.AcceptedAnswerId, 
    p.AnswerCount, 
    p.FavoriteCount, 
    p.CommentCount
HAVING 
    COUNT(DISTINCT c.Id) >= 5 
    OR COUNT(DISTINCT v.Id) >= 10 
    OR COUNT(DISTINCT bh.Id) >= 3
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC,
    CASE 
        WHEN p.PostTypeId = 1 THEN 1
        WHEN p.PostTypeId = 2 THEN 2
        ELSE 3
    END,
    p.CreationDate DESC
LIMIT 10000;