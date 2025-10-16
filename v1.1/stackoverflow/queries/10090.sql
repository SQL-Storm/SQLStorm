SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN p.Id END) AS TotalDuplicates,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.CreationDate) AS FirstPostDate,
    MAX(p.LastActivityDate) AS LastActivityDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedPost,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    MAX(b.Date) AS LastBadgeEarned,
    STRING_AGG(DISTINCT t.TagName, ', ') AS MostCommonTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId AND t.IsRequired = FALSE
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 1000
    AND (p.ViewCount > 100 OR p.ViewCount IS NULL)
    AND (p.Score > 0 OR p.Score IS NULL)
    AND (ph.PostHistoryTypeId = 10 OR ph.PostHistoryTypeId IS NULL)
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalPosts DESC,
    TotalQuestions DESC;