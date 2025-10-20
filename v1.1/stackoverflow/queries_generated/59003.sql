-- {"query": "59003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 658} 
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
    STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
    COUNT(DISTINCT bh.Id) as HistoryCount,
    MAX(bh.CreationDate) as LastEditDate,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        ELSE 'Unknown'
    END as PostType,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
    END as PostStatus,
    COALESCE(p.AnswerCount, 0) as AnswerCount,
    COALESCE(p.FavoriteCount, 0) as FavoriteCount,
    COALESCE(p.CommentCount, 0) as ActualCommentCount,
    COUNT(DISTINCT pl.Id) as LinkCount,
    COUNT(DISTINCT b.Id) as BadgeCount,
    STRING_AGG(DISTINCT CONCAT(u2.DisplayName, ' (', u2.Reputation, ')'), ', ') as TopVoters
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
LEFT JOIN PostHistory bh ON p.Id = bh.PostId
LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN Users u2 ON v.UserId = u2.Id
WHERE 
    p.CreationDate >= '2020-01-01'
    AND p.PostTypeId IN (1, 2)
    AND p.Score >= 0
    AND p.ViewCount > 100
    AND u.Reputation >= 1000
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, 
    u.DisplayName, u.Reputation, p.PostTypeId, p.ClosedDate, 
    p.CommunityOwnedDate, p.AnswerCount, p.FavoriteCount, 
    p.CommentCount, p.Tags
HAVING 
    COUNT(DISTINCT c.Id) > 5
    AND COUNT(DISTINCT v.Id) > 10
    AND COUNT(DISTINCT bh.Id) > 3
    AND COUNT(DISTINCT pl.Id) > 1
    AND COUNT(DISTINCT b.Id) > 0
ORDER BY 
    p.Score DESC,
    p.ViewCount DESC,
    p.CreationDate DESC
LIMIT 1000;