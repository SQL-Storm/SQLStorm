-- {"query": "33011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 377} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalQuestions,
    COUNT(DISTINCT a.Id) AS TotalAnswers,
    AVG(p.Score) AS AvgQuestionScore,
    AVG(a.Score) AS AvgAnswerScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    COUNT(DISTINCT pl.Id) AS TotalLinks,
    COUNT(DISTINCT c2.Id) AS TotalPostHistories,
    MAX(p.CreationDate) AS LastQuestionDate,
    MAX(a.CreationDate) AS LastAnswerDate
FROM 
    Users u
LEFT JOIN 
    Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN 
    Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
LEFT JOIN 
    Votes v ON v.PostId = p.Id OR v.PostId = a.Id
LEFT JOIN 
    Comments c ON c.PostId = p.Id OR c.PostId = a.Id
LEFT JOIN 
    Badges b ON b.UserId = u.Id
LEFT JOIN 
    PostLinks pl ON pl.PostId = p.Id OR pl.PostId = a.Id
LEFT JOIN 
    PostHistory c2 ON c2.PostId = p.Id OR c2.PostId = a.Id
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
ORDER BY 
    u.Reputation DESC
LIMIT 100;