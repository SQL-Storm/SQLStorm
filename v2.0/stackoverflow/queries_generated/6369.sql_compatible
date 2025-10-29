SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestUserCreation,
    AVG(p.Score) AS AvgPostScore,
    MAX(ph.RevisionGUID) AS LastRevisionGUID,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId ELSE NULL END) AS TotalDuplicatePosts,
    MAX(p.LastActivityDate) AS MostRecentActivity,
    -- Use ARRAY_AGG + DISTINCT and order inside a subquery-style expression for broader dialect compatibility
    (SELECT STRING_AGG(t2.TagName, ', ' ORDER BY t2.cnt DESC)
     FROM (
        SELECT t.TagName, COUNT(*) AS cnt
        FROM Tags t
        JOIN Posts p2 ON p2.Id = t.ExcerptPostId
        WHERE p2.OwnerUserId = u.Id
        GROUP BY t.TagName
     ) t2
    ) AS TopTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Id IN (
        SELECT UserId 
        FROM Badges 
        WHERE Class = 1 AND TagBased = FALSE
    )
GROUP BY 
    u.DisplayName, u.Id
HAVING 
    AVG(p.Score) > 0
ORDER BY 
    TotalPosts DESC, 
    AvgPostScore DESC;