SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    COUNT(DISTINCT p.AcceptedAnswerId) AS TotalAcceptedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) * 
    (SELECT AVG(AnswerCount) FROM Posts WHERE PostTypeId = 1) AS AverageAnswersPerQuestion,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalViewsOnQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE 0 END) AS TotalViewsOnAnswers,
    MAX(u.LastAccessDate) AS LastAccess,
    MIN(p.CreationDate) AS FirstPostDate,
    MAX(p.LastActivityDate) AS LastActivityDate,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    SUM(v.BountyAmount) AS TotalBounty,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN p.Id ELSE NULL END) AS TotalDuplicates,
    SUM(CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS TotalClosedQuestions,
    STRING_AGG(DISTINCT t.TagName, ', ') AS TagList
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Votes v ON u.Id = v.UserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN
    Tags t ON t.ExcerptPostId = p.Id
WHERE 
    (u.Reputation > 10000 OR u.Reputation IS NULL)
    AND (p.CreationDate >= '2020-01-01' OR p.CreationDate IS NULL)
    AND (ph.Comment IS NOT NULL AND ph.Comment NOT LIKE '%Duplicate%')
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalScore DESC, 
    TotalPosts DESC;