-- {"query": "42046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 415} 

SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    u.Reputation, 
    COUNT(p.Id) AS TotalPosts, 
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions, 
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers, 
    SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) AS TotalScore, 
    COUNT(DISTINCT ph.Id) AS TotalEdits, 
    COUNT(DISTINCT v.Id) AS TotalVotes, 
    COUNT(DISTINCT b.Id) AS TotalBadges, 
    COUNT(DISTINCT t.Id) AS TotalTagsEdited
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (5, 8, 9)
LEFT JOIN 
    Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostHistory pht ON u.Id = pht.UserId AND pht.PostHistoryTypeId = 6
LEFT JOIN 
    Tags t ON pht.PostId = t.WikiPostId
WHERE 
    u.CreationDate <= NOW() - INTERVAL '1 year'
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(p.Id) > 10 AND SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) > 100
ORDER BY 
    TotalScore DESC, TotalPosts DESC
LIMIT 100;
