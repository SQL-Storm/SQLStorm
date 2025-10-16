-- {"query": "10091.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 399} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 1) AS GoldBadgeCount,
    (SELECT COUNT(DISTINCT TagName) FROM Tags t WHERE t.ExcerptPostId = p.Id) AS TagCount,
    (SELECT STRING_AGG(Text, ', ') FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10) AS CloseReasons,
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
    AND p.LastActivityDate > DATEADD(month, -12, CURRENT_TIMESTAMP)
GROUP BY 
    u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    TotalPosts DESC, 
    LatestAccountActivity DESC
LIMIT 100;
