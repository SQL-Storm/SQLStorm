SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 1) AS GoldBadgeCount,
    (SELECT COUNT(*) FROM Votes WHERE PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) AND VoteTypeId = 2) AS TotalUpVotesGiven,
    (SELECT STRING_AGG(TagName, ', ') FROM Tags t JOIN Posts post ON t.ExcerptPostId = post.Id WHERE post.OwnerUserId = u.Id) AS FavoriteTags,
    (SELECT COUNT(*) FROM Comments WHERE UserId = u.Id) AS TotalCommentsMade,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 1000
    AND p.LastActivityDate > (cast('2024-10-01' as date) - INTERVAL '12 months')
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalPosts DESC, GoldBadgeCount DESC;