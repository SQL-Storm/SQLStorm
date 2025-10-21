-- {"query": "42051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 318} 

SELECT 
    u.DisplayName AS User,
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    SUM(p.Score) AS TotalScore,
    COUNT(DISTINCT ph.Id) AS TotalEdits,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT b.Id) AS TotalBadges
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
    u.Id, u.DisplayName
HAVING 
    COUNT(p.Id) > 10 AND SUM(p.Score) > 100
ORDER BY 
    TotalScore DESC, TotalPosts DESC
LIMIT 100;
