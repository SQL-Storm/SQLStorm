-- {"query": "10036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 449} 

SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId ELSE NULL END) AS TotalDownVotes,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.Score) AS LowestScoredPost,
    STRING_AGG(DISTINCT t.TagName, ', ') AS MostCommonTags,
    AVG(p.ViewCount) AS AvgViewCount,
    AVG(p.AnswerCount) AS AvgAnswerCount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
WHERE 
    u.Reputation > 10000 AND 
    p.CreationDate >= DATEADD(year, -5, GETDATE()) AND 
    v.VoteTypeId IN (2, 3) AND 
    ph.Comment IS NOT NULL
GROUP BY 
    u.DisplayName, u.Reputation, u.Location
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 50
ORDER BY 
    TotalPosts DESC, 
    TotalQuestions DESC;
