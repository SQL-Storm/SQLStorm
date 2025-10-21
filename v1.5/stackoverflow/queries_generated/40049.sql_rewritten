-- {"query": "40049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 169} 
SELECT 
    COUNT(DISTINCT p.Id) AS PostCount,
    COUNT(DISTINCT u.Id) AS UserCount,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    COUNT(DISTINCT v.PostId) AS VoteCount,
    COUNT(DISTINCT t.Id) AS TagCount
FROM 
    Posts p
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Tags t ON t.ExcerptPostId = p.Id
WHERE 
    p.CreationDate >= DATE_TRUNC('month', cast('2024-10-01' as date)) - INTERVAL '1 year';