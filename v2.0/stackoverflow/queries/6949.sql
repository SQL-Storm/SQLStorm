-- {"query": "6949.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 517}
SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE NULL END) AS TotalQuestions,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id ELSE NULL END) AS TotalAcceptedQuestions,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.CreationDate) AS FirstPostDate,
    MAX(p.LastActivityDate) AS LastActiveDate,
    SUM(p.ViewCount) AS TotalViews,
    SUM(COALESCE(v.BountyAmount, 0)) AS TotalBounty,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LastClosedPost,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN cl.Name ELSE NULL END) AS LastClosedReason,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS LastClosedReasonId
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35)
LEFT JOIN 
    CloseReasonTypes cl ON ph.Comment = CAST(cl.Id AS varchar)
WHERE 
    u.Reputation > 10000
    AND p.LastEditDate > (CAST('2024-10-01' AS date) - INTERVAL '1 year')
    AND p.ViewCount > 1000
GROUP BY 
    u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, 
    TotalViews DESC;