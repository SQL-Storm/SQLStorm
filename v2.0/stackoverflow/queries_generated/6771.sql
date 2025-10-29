-- {"query": "6771.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 413} 

SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(ph.CreationDate) AS LatestPostEdit,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 1 THEN v.PostId ELSE NULL END) AS AcceptedAnswers,
    COUNT(DISTINCT CASE WHEN p.ClosedDate IS NOT NULL THEN p.Id ELSE NULL END) AS TotalClosedPosts,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.PostId ELSE NULL END) AS TotalDuplicatePosts,
    AVG(p.Score) AS AveragePostScore,
    STRING_AGG(DISTINCT t.TagName, ', ') AS PopularTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation >= 1000
    AND u.Id NOT IN (
        SELECT DISTINCT OwnerUserId FROM Posts WHERE PostTypeId = 3
    )
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    AVG(p.Score) DESC, 
    TotalClosedPosts DESC;
