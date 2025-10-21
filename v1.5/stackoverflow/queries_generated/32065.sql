-- {"query": "32065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 301} 

SELECT 
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
    AVG(p.Score) AS AverageScore,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT ph.Id) AS EditHistoryCount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Comments c ON u.Id = c.UserId
LEFT JOIN 
    PostHistory ph ON u.Id = ph.UserId
WHERE 
    u.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
AND 
    u.Reputation > 1000
AND 
    p.PostTypeId IN (1, 2) -- Questions and Answers
GROUP BY 
    u.DisplayName, u.Reputation
HAVING 
    TotalPosts > 10
ORDER BY 
    TotalUpvotes DESC, TotalDownvotes ASC, AverageScore DESC;
