-- {"query": "32029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 330} 

SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    u.Reputation, 
    COUNT(DISTINCT p.Id) AS TotalPosts, 
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount, 
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount, 
    AVG(CAST(p.Score AS FLOAT)) AS AvgPostScore, 
    COUNT(DISTINCT c.Id) AS TotalComments, 
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges, 
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges, 
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges, 
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS TotalUpVotes, 
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS TotalDownVotes
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments c ON u.Id = c.UserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Votes v ON u.Id = v.UserId
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
ORDER BY 
    u.Reputation DESC, TotalPosts DESC
LIMIT 100;
