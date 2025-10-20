-- {"query": "42016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 361} 
SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    u.Reputation, 
    COUNT(DISTINCT p.Id) AS TotalPosts, 
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions, 
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers, 
    SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) AS TotalPositiveScore, 
    COUNT(DISTINCT v.Id) AS TotalVotesReceived, 
    COUNT(DISTINCT c.Id) AS TotalCommentsReceived, 
    COUNT(DISTINCT b.Id) AS TotalBadgesEarned, 
    MAX(ph.CreationDate) AS LastActivityDate
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON u.Id = v.UserId
LEFT JOIN 
    Comments c ON u.Id = c.UserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostHistory ph ON u.Id = ph.UserId
WHERE 
    u.CreationDate <= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 10 AND SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) > 100
ORDER BY 
    TotalPositiveScore DESC, TotalPosts DESC
LIMIT 100;