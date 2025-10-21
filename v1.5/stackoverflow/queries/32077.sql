-- {"query": "32077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 298} 
SELECT 
    u.DisplayName, 
    u.Reputation, 
    p.Id AS PostId, 
    p.Title, 
    p.CreationDate AS PostCreationDate, 
    p.Score, 
    COUNT(DISTINCT c.Id) AS CommentCount, 
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    ARRAY_AGG(DISTINCT b.Name) AS Badges
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3) 
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    u.Reputation > 1000
    AND p.Score > 0
    AND p.ViewCount > 100
    AND p.CreationDate BETWEEN '2020-01-01' AND '2022-12-31'
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, p.Id, p.Title, p.CreationDate, p.Score
HAVING 
    COUNT(DISTINCT v.Id) > 10
ORDER BY 
    COUNT(DISTINCT v.Id) DESC, p.Score DESC;