-- {"query": "59002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 391} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerDisplayName,
    u.Reputation,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT v.Id) as VoteCount,
    COUNT(DISTINCT ph.Id) as HistoryCount,
    COUNT(DISTINCT pl.Id) as LinkCount,
    STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
    STRING_AGG(DISTINCT b.Name, ', ') as Badges,
    MAX(ph.CreationDate) as LastActivityDate
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN (
    SELECT PostId, unnest(string_to_array(Tags, '><')) as TagName
    FROM Posts
    WHERE Tags IS NOT NULL AND Tags != ''
) t ON p.Id = t.PostId
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= '2022-01-01'
    AND p.Score >= 0
    AND u.Reputation >= 100
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT v.Id) > 5
    AND COUNT(DISTINCT c.Id) > 2
    AND COUNT(DISTINCT ph.Id) > 1
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 10000;