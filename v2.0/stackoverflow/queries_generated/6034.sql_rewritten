-- {"query": "6034.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 351} 
SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS HighestQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(p.ViewCount) AS MaxViewCount,
    MIN(ph.CreationDate) AS FirstPostEdit,
    MAX(CASE WHEN p.PostTypeId = 1 THEN v.BountyAmount ELSE 0 END) AS MaxQuestionBounty
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    (SELECT 
         ph.PostId, 
         ph.CreationDate
     FROM 
         PostHistory ph
     WHERE 
         ph.PostHistoryTypeId = 4
     GROUP BY 
         ph.PostId, 
         ph.CreationDate
     HAVING 
         COUNT(ph.Id) = 1) AS FirstEdit ON p.Id = FirstEdit.PostId
WHERE 
    u.Reputation > 1000
    AND u.Id NOT IN (SELECT AccountId FROM Users WHERE AccountId > 0)
GROUP BY 
    u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalPosts DESC;