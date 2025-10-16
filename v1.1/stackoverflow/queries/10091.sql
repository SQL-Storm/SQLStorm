SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 1) AS GoldBadgeCount,
    (SELECT COUNT(DISTINCT t.TagName) FROM Tags t WHERE t.ExcerptPostId = p.Id) AS TagCount,
    (SELECT STRING_AGG(ph.Text, ', ') FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10) AS CloseReasons,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS LinkedPostsCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpvoteCount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    u.Reputation > 1000
    AND p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '12' MONTH)
GROUP BY 
    u.DisplayName, 
    u.Reputation,
    u.CreationDate,
    p.LastActivityDate,
    u.Id,
    p.Id
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    TotalPosts DESC, 
    LatestAccountActivity DESC
LIMIT 100;