-- {"query": "6008.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 421} 

SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS TotalPositiveScorePosts,
    MAX(p.LastActivityDate) AS LastActivePost,
    MAX(CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.ClosedDate ELSE NULL END) AS LastClosedQuestion,
    MIN(ph.CreationDate) AS FirstPostEdit,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId ELSE NULL END) AS TotalDuplicateLinks,
    COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.TagBased ELSE NULL END) AS TotalTagBasedBadges,
    COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.Class ELSE NULL END) AS TotalNamedBadges
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 10000
    AND u.LastAccessDate > (CURRENT_TIMESTAMP - INTERVAL '1 year')
    AND p.CreationDate IS NOT NULL
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    AVG(p.Score) > 0
ORDER BY 
    u.Reputation DESC
LIMIT 100;
