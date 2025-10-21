-- {"query": "41047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 335} 

SELECT 
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.Body AS PostBody,
    u.DisplayName AS PostOwnerDisplayName,
    u.Reputation AS PostOwnerReputation,
    COUNT(DISTINCT v.Id) AS PostVoteCount,
    COUNT(DISTINCT c.Id) AS PostCommentCount,
    COUNT(DISTINCT ph.Id) AS PostHistoryCount,
    COUNT(DISTINCT pl.Id) AS PostLinkCount,
    COUNT(DISTINCT t.Id) AS PostTagCount
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
    (SELECT PostId, COUNT(DISTINCT Id) AS Id FROM Tags GROUP BY PostId) t ON p.Id = t.PostId
GROUP BY 
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Body, u.DisplayName, u.Reputation
ORDER BY 
    p.CreationDate DESC, p.Score DESC
LIMIT 100;
