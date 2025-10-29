-- {"query": "6590.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 334} 

SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId ELSE NULL END) AS TotalDownVotes,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestUser,
    STRING_AGG(DISTINCT t.TagName, ', ') AS PopularTags,
    AVG(p.Score) AS AvgScorePerPost
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON pl.RelatedPostId = t.Id
WHERE 
    p.PostTypeId IN (1, 2) 
    AND u.Reputation > 100
    AND p.CreationDate BETWEEN DATEADD(year, -1, GETDATE()) AND GETDATE() 
GROUP BY 
    u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 10 
ORDER BY 
    AvgScorePerPost DESC, 
    TotalUpVotes DESC;
