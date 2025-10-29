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
    MAX(p.CreationDate) AS LastPostDate,
    SUM(v.BountyAmount) AS TotalBountyAmount,
    CASE 
        WHEN u.UpVotes >= u.DownVotes THEN 'NetPositive'
        WHEN u.UpVotes < u.DownVotes THEN 'NetNegative'
        ELSE 'NetNeutral'
    END AS ReputationTrend,
    STRING_AGG(DISTINCT t.TagName, ', ') AS PopularTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 100
    AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    u.Reputation DESC, TotalPosts DESC;