-- {"query": "42035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 234} 
SELECT 
    u.DisplayName,
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    SUM(p.Score) AS TotalScore,
    COUNT(DISTINCT ph.Id) AS TotalEdits,
    COUNT(DISTINCT v.Id) AS TotalVotes
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.CreationDate >= DATE_TRUNC('month', cast('2024-10-01' as date)) - INTERVAL '1 year'
GROUP BY 
    u.DisplayName
HAVING 
    COUNT(p.Id) > 100
ORDER BY 
    TotalScore DESC, 
    TotalPosts DESC
LIMIT 50;