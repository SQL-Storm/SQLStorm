-- {"query": "59084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 531} 
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
    p.FavoriteCount,
    p.Tags,
    STRING_AGG(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN 'UpVote' WHEN v.VoteTypeId = 3 THEN 'DownVote' END, ', ') as VoteTypes,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT ph.Id) as HistoryCount,
    COUNT(DISTINCT pl.Id) as LinkCount,
    STRING_AGG(DISTINCT bt.Name, ', ') as BadgeNames,
    STRING_AGG(DISTINCT t.TagName, ', ') as TagNames
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Badges bt ON u.Id = bt.UserId
LEFT JOIN (
    SELECT DISTINCT Id, TagName FROM Tags
) t ON p.Tags LIKE '%' || t.TagName || '%'
WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= '2020-01-01'
    AND p.CreationDate <= '2023-12-31'
    AND p.Score >= 0
    AND p.ViewCount >= 100
    AND p.AnswerCount >= 1
GROUP BY 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.CreationDate, 
    u.DisplayName, 
    u.Reputation, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    p.Tags
HAVING 
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN 'UpVote' WHEN v.VoteTypeId = 3 THEN 'DownVote' END) > 10
    AND COUNT(DISTINCT c.Id) > 5
    AND COUNT(DISTINCT pl.Id) > 0
    AND COUNT(DISTINCT bt.Name) > 2
ORDER BY 
    p.Score DESC,
    p.ViewCount DESC,
    p.CreationDate DESC
LIMIT 10000;