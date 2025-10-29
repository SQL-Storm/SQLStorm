-- {"query": "6093.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 417} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    b.Class,
    t.TagName,
    ph.RevisionGUID,
    ph.Comment,
    CASE 
        WHEN p.Score > 0 THEN 'Positive'
        WHEN p.Score < 0 THEN 'Negative'
        ELSE 'Neutral'
    END AS ScoreTrend
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    (SELECT 
        ph.PostId, 
        MAX(ph.CreationDate) AS LatestRevision
     FROM 
        PostHistory ph
     GROUP BY 
        ph.PostId) AS latest_ph ON p.Id = latest_ph.PostId
WHERE 
    (u.Reputation > 1000 OR u.DisplayName LIKE '%StackOverflow%')
    AND (p.Score > 0 OR p.Score < 0)
    AND (ph.PostId IS NOT NULL OR latest_ph.LatestRevision IS NOT NULL)
GROUP BY 
    u.DisplayName, u.Reputation, b.Class
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;
