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
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS TotalGoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS TotalSilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS TotalBronzeBadges,
    SUM(v.BountyAmount) AS TotalBountyGiven,
    SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS TotalPositiveScoreComments,
    MAX(c.CreationDate) AS LastCommented,
    COALESCE(SUM(p.Score), 0) / NULLIF(COUNT(DISTINCT p.Id),0) AS AvgScorePerPost
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 100
    AND u.Id NOT IN (SELECT Id FROM Users WHERE AccountId IS NOT NULL)
    AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 years')
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    AvgScorePerPost DESC, 
    TotalPositiveScorePosts DESC;