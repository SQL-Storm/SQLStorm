-- {"query": "40010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 147} 
SELECT 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT u.Id) AS TotalUsers,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    COUNT(DISTINCT v.PostId) AS TotalVotes
FROM 
    Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    JOIN Badges b ON u.Id = b.UserId
    JOIN Votes v ON p.Id = v.PostId
WHERE 
    p.CreationDate >= DATE_TRUNC('month', cast('2024-10-01' as date)) - INTERVAL '1 year'
    AND u.Reputation > 1000;