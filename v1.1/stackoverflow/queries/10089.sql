SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.AnswerCount, 0) ELSE 0 END) AS TotalAnswersToQuestions,
    SUM(COALESCE(v.BountyAmount, 0)) AS TotalBountyAmount,
    MAX(u.LastAccessDate) AS LastAccessDate,
    MIN(p.CreationDate) AS EarliestPostDate,
    MAX(ph.CreationDate) AS LastPostHistoryUpdate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS LastCloseReason,
    -- Replaced STRING_AGG(DISTINCT ... ORDER BY ...) with aggregation without ORDER BY for broader compatibility.
    -- This will produce a comma-separated list of distinct tag names but order is not guaranteed.
    STRING_AGG(DISTINCT t.TagName, ', ') AS PopularTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5' YEAR)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    TotalScore DESC, 
    TotalPosts DESC;