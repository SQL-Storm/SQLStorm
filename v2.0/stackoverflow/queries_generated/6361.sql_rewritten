-- {"query": "6361.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 468} 
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
    COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.Id ELSE NULL END) AS TotalBadges,
    MAX(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) AS LastGoldBadge,
    MAX(CASE WHEN b.Class = 2 THEN b.Date ELSE NULL END) AS LastSilverBadge,
    MAX(CASE WHEN b.Class = 3 THEN b.Date ELSE NULL END) AS LastBronzeBadge
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    u.Reputation > 10000
    AND u.LastAccessDate > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year')
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    u.Reputation DESC, 
    TotalPositiveScorePosts DESC
LIMIT 100;