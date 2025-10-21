-- {"query": "45029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 358}
SELECT
    p.Id AS PostId,
    p.Title,
    u.DisplayName AS PostOwner,
    u.Reputation,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    AVG(DISTINCT v2.Score) AS AverageRelatedPostScore,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateCount,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ph.CreationDate) AS MedianEditTime
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Posts v2 ON pl.RelatedPostId = v2.Id
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    p.PostTypeId = 1
    AND u.Reputation > 1000
    AND p.CreationDate > '2015-01-01'
GROUP BY 
    p.Id, p.Title, u.DisplayName, u.Reputation
ORDER BY 
    VoteCount DESC, Reputation DESC
LIMIT 500;
