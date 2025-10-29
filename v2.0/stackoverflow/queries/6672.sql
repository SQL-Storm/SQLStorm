-- {"query": "6672.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 572}
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id ELSE NULL END) AS TotalPositiveScorePosts,
    COUNT(DISTINCT CASE WHEN p.ClosedDate IS NOT NULL THEN p.Id ELSE NULL END) AS TotalClosedPosts,
    MAX(p.LastActivityDate) AS LastActivityDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LastClosedDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 101 THEN ph.CreationDate ELSE NULL END) AS LastDuplicateClosedDate,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViewCount,
    MAX(p.AnswerCount) AS MaxAnswerCount,
    MAX(v.BountyAmount) AS MaxBountyAmount,
    SUBSTRING(u.AboutMe FROM 1 FOR 50) AS ShortAboutMe,
    STRING_AGG(t.TagName, ', ' ORDER BY t.TagName) AS TagList,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY MAX(p.LastActivityDate) DESC) AS RecentActivityRank
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2' YEAR)
    AND (u.Location IS NOT NULL OR u.WebsiteUrl IS NOT NULL)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.AboutMe
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    AvgScore DESC, 
    TotalPosts DESC;