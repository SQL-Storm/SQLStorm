-- {"query": "6755.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 598}
SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    COUNT(DISTINCT p.AcceptedAnswerId) AS TotalAcceptedAnswers,
    COUNT(DISTINCT pl.RelatedPostId) AS TotalLinkedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id ELSE NULL END) AS TotalClosedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.Id ELSE NULL END) AS TotalReopenedPosts,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id ELSE NULL END) AS TotalDownVotes,
    SUM(COALESCE(p.Score, 0)) AS TotalScore,
    SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MIN(p.CreationDate) AS EarliestPost,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    STRING_AGG(DISTINCT CASE WHEN t.TagName IS NOT NULL THEN t.TagName ELSE NULL END, ', ') AS PopularTags,
    STRING_AGG(DISTINCT CASE WHEN b.Name IS NOT NULL THEN b.Name ELSE NULL END, ', ') AS EarnedBadges
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    u.Reputation > 100
    AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalViews DESC, TotalPosts DESC
LIMIT 100;