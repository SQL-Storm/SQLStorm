-- {"query": "32091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 284} 

SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(p.Score) AS TotalScore,
    COUNT(DISTINCT a.Id) AS TotalAnswers,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE NULL END) AS AverageAnswersPerQuestion,
    MAX(p.ViewCount) AS MaxViewCount,
    COUNT(DISTINCT pe.Id) AS TotalPostEdits,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    SUM(v.BountyAmount) AS TotalBountyAwarded
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Posts a ON p.Id = a.ParentId
LEFT JOIN 
    PostHistory pe ON p.Id = pe.PostId AND pe.PostHistoryTypeId IN (4, 5, 6)
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 1000
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location
ORDER BY 
    TotalScore DESC, u.Reputation DESC;
