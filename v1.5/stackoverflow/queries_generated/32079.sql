-- {"query": "32079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 218} 

SELECT 
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(p.Id) AS TotalPosts,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS TotalQuestions,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS TotalAnswers,
    COUNT(b.Id) AS BadgesCount,
    SUM(v.BountyAmount) AS TotalBountyAmount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (8, 9)
WHERE 
    u.Reputation > 1000 AND u.CreationDate >= '2020-01-01'
GROUP BY 
    u.DisplayName, u.Reputation
HAVING 
    COUNT(p.Id) > 50
ORDER BY 
    TotalPosts DESC, TotalBountyAmount DESC;
