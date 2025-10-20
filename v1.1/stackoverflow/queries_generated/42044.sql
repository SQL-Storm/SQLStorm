-- {"query": "42044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 332} 

SELECT 
    p.Id, 
    p.Title, 
    COUNT(v.Id) AS TotalVotes, 
    COUNT(DISTINCT c.Id) AS TotalComments, 
    COUNT(DISTINCT ph.Id) AS TotalEdits, 
    COUNT(DISTINCT b.Id) AS TotalBadges, 
    u.DisplayName, 
    u.Reputation, 
    u.CreationDate, 
    u.UpVotes, 
    u.DownVotes, 
    u.Views, 
    u.Location, 
    u.AboutMe, 
    u.ProfileImageUrl, 
    u.EmailHash, 
    u.AccountId
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
    Badges b ON u.Id = b.UserId
WHERE 
    p.PostTypeId = 1 
    AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY 
    p.Id, 
    u.Id
HAVING 
    COUNT(v.Id) > 10 
    AND COUNT(DISTINCT c.Id) > 5
ORDER BY 
    p.Score DESC, 
    u.Reputation DESC
LIMIT 100;
