-- {"query": "6776.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 395} 

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
    Tags t ON t.ExcerptPostId = p.Id
LEFT JOIN 
    PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
WHERE 
    (p.Score > 0 OR p.Score < 0)
    AND u.Reputation > 100
    AND (b.Class IS NOT NULL OR t.TagName IS NOT NULL)
    AND ph.RevisionGUID IS NOT NULL
GROUP BY 
    u.DisplayName,
    u.Reputation,
    b.Class,
    t.TagName,
    ph.RevisionGUID,
    ph.Comment
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 5
ORDER BY 
    u.Reputation DESC,
    TotalPosts DESC;
