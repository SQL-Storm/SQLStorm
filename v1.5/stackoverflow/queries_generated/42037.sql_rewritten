-- {"query": "42037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 351} 
SELECT 
    u.DisplayName,
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) AS TotalPositiveScore,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (24, 33, 34) THEN ph.PostId END) AS TotalEditsAndNotices,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2, 3) THEN v.PostId END) AS TotalVotes,
    COUNT(DISTINCT CASE WHEN c.Id IS NOT NULL THEN c.PostId END) AS TotalComments,
    COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.UserId END) AS TotalBadges
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    u.CreationDate >= '2020-01-01' AND u.CreationDate < '2021-01-01'
GROUP BY 
    u.DisplayName
HAVING 
    COUNT(p.Id) > 10 AND SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) > 100
ORDER BY 
    TotalPositiveScore DESC, TotalPosts DESC;