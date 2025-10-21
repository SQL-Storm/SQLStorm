-- {"query": "40014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 171} 
SELECT 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT u.Id) AS TotalUsers,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT t.Id) AS TotalTags
FROM 
    Posts p
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId;