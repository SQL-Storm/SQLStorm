SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) AS TotalWikis,
    COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id END) AS TotalPositiveScorePosts,
    MAX(p.Score) AS HighestScore,
    MIN(p.Score) AS LowestScore,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActivityDate,
    MIN(p.CreationDate) AS FirstPostDate,
    MAX(u.LastAccessDate) AS LastUserAccessDate,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    MAX(CASE WHEN b.Class = 1 THEN b.Date END) AS LatestGoldBadge,
    MAX(CASE WHEN b.Class = 2 THEN b.Date END) AS LatestSilverBadge,
    MAX(CASE WHEN b.Class = 3 THEN b.Date END) AS LatestBronzeBadge,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN p.Id END) AS TotalDuplicatePosts,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) AS TotalDownVotes,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.PostId END) AS TotalClosedPosts,
    COUNT(DISTINCT CASE WHEN t.IsRequired = TRUE THEN t.Id END) AS TotalRequiredTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
    AND u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
    AND (p.ViewCount > 100 OR p.AnswerCount > 0)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
ORDER BY 
    TotalViews DESC, TotalPosts DESC;