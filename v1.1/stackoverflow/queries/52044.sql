-- {"query": "52044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 277} 
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    AVG(p.Score) AS AvgPostScore,
    SUM(v.TotalUpvotes) AS TotalUpvotesReceived,
    COUNT(b.Id) AS TotalBadges,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS NumQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS NumAnswers,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE NULL END) AS AvgAnswersPerQuestion
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
LEFT JOIN 
    (SELECT PostId, COUNT(*) AS TotalUpvotes 
     FROM Votes 
     WHERE VoteTypeId = 2 
     GROUP BY PostId) v ON p.Id = v.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 0
ORDER BY 
    TotalUpvotesReceived DESC, TotalBadges DESC, Reputation DESC
LIMIT 100;