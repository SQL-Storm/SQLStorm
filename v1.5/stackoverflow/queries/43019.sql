SELECT 
    u.DisplayName, 
    u.Reputation, 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalClosedQuestions,
    SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalReopenedQuestions,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived,
    AVG(p.ViewCount) AS AvgPostViewCount,
    MAX(p.Score) AS HighestPostScore,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS TotalGoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS TotalSilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS TotalBronzeBadges,
    MAX(p.CreationDate) AS MostRecentPostDate
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (10, 11)
LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE u.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '2 years')
GROUP BY u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 10
ORDER BY TotalUpvotesReceived DESC, TotalPosts DESC, Reputation DESC;