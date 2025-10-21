-- {"query": "42093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 331} 

SELECT 
    p.Id, 
    p.Title, 
    count(v.Id) AS VoteCount,
    u.DisplayName,
    u.Reputation,
    count(c.Id) AS CommentCount,
    count(ph.Id) AS PostHistoryCount,
    count(pl.Id) AS PostLinkCount,
    count(b.Id) AS BadgeCount,
    count(t.Id) AS TagCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
WHERE 
    p.CreationDate >= '2020-01-01' 
    AND p.PostTypeId = 1
GROUP BY 
    p.Id, u.Id
HAVING 
    count(v.Id) > 10 
    AND count(c.Id) > 5
ORDER BY 
    count(v.Id) DESC, 
    count(c.Id) DESC 
LIMIT 100;
