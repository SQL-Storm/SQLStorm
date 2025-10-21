-- {"query": "32027.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 326} 

SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    u.Reputation, 
    COUNT(p.Id) AS TotalPosts, 
    SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionsPosted, 
    SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswersPosted, 
    AVG(p.Score) AS AveragePostScore, 
    MAX(p.ViewCount) AS MaxViewCount, 
    SUM(vt1.upvotes) AS TotalUpVotes, 
    SUM(vt2.downvotes) AS TotalDownVotes, 
    SUM(b.Class) AS BadgeScore
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    (SELECT PostId, COUNT(*) AS upvotes FROM Votes WHERE VoteTypeId = 2 GROUP BY PostId) vt1 on vt1.PostId = p.Id
LEFT JOIN 
    (SELECT PostId, COUNT(*) AS downvotes FROM Votes WHERE VoteTypeId = 3 GROUP BY PostId) vt2 on vt2.PostId = p.Id
LEFT JOIN 
    Badges b ON u.Id = b.UserId
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(p.Id) > 10 
    AND AVG(p.Score) > 0
ORDER BY 
    TotalPosts DESC, AveragePostScore DESC
LIMIT 100;
