-- {"query": "6541.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 499} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswersToQuestions,
    SUM(v.BountyAmount) AS TotalBountyAmount,
    MAX(u.LastAccessDate) AS LastAccess,
    MIN(u.CreationDate) AS AccountCreated,
    b.Name AS TopBadge,
    t.TagName AS MostUsedTag
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    Tags t ON p.Tags IS NOT NULL AND t.Id = ANY(STRING_TO_ARRAY(p.Tags, ',')::INTEGER[])
LEFT JOIN 
    (SELECT UserId, Name, MAX(Date) AS MaxDate FROM Badges GROUP BY UserId, Name) bt ON u.Id = bt.UserId
WHERE 
    u.Reputation > 10000 AND 
    p.LastActivityDate > (CURRENT_DATE - INTERVAL '1 year') AND 
    p.Score > 0 AND 
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) > 0
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 10 AND 
    MAX(u.LastAccessDate) > (CURRENT_DATE - INTERVAL '30 days')
ORDER BY 
    u.Reputation DESC, 
    TotalScore DESC
LIMIT 100;
