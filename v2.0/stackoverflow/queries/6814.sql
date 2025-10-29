-- {"query": "6814.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 414}
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId IN 
        (SELECT Id FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1 AND Score > 100)
    ) AS HighlyUpvotedQuestions,
    (SELECT STRING_AGG(t2.TagName, ', ') FROM Tags t2 WHERE t2.Id IN 
        (SELECT DISTINCT t3.Id FROM Posts p2 JOIN Tags t3 ON t3.ExcerptPostId = p2.Id WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1)
    ) AS FavoriteTags,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId IN 
        (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) AND ph.PostHistoryTypeId = 10) AS TotalCloseVotes
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 6
WHERE 
    u.Reputation > 10000
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, TotalPosts DESC;