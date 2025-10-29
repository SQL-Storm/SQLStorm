-- {"query": "6232.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 403} 

SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    AVG(p.Score) AS AvgScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswers,
    MAX(p.LastActivityDate) AS LastActivity,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.ClosedDate ELSE NULL END) AS LastQuestionClosed,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId ELSE NULL END) AS TotalDownVotes,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    MAX(ph.CreationDate) AS LastPostHistory
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    (u.Reputation > 10000 OR u.Reputation IS NULL)
    AND (p.PostTypeId IN (1, 2) OR p.PostTypeId IS NULL)
    AND (v.VoteTypeId IN (2, 3) OR v.VoteTypeId IS NULL)
    AND (b.Class = 1 OR b.Class IS NULL)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    AvgScore DESC, 
    TotalPosts DESC
LIMIT 100;
