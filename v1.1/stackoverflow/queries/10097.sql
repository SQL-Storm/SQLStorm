-- {"query": "10097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 648} 
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id ELSE NULL END) AS TotalPositiveScorePosts,
    MAX(p.Score) AS HighestScore,
    MIN(p.Score) AS LowestScore,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswersToQuestions,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.FavoriteCount ELSE 0 END) AS TotalFavoritesToQuestions,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.CommentCount ELSE 0 END) AS TotalCommentsToQuestions,
    SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS TotalClosedPosts,
    SUM(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END) AS TotalCommunityOwnedPosts,
    SUM(CASE WHEN p.LastEditDate > p.CreationDate THEN 1 ELSE 0 END) AS TotalEditedPosts,
    SUM(v.BountyAmount) AS TotalBountyAmount,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.UserId = u.Id AND b.Class = 1
    ) AS GoldBadgeCount,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.UserId = u.Id AND b.Class = 2
    ) AS SilverBadgeCount,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.UserId = u.Id AND b.Class = 3
    ) AS BronzeBadgeCount,
    (
        SELECT STRING_AGG(TagName, ', ') 
        FROM Tags t 
        JOIN Posts pr ON t.ExcerptPostId = pr.Id
        WHERE pr.OwnerUserId = u.Id
    ) AS OwnedTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
WHERE 
    u.Reputation > 100
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, TotalViews DESC;