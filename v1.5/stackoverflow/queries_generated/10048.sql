-- {"query": "10048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 483} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswersToQuestions,
    MAX(u.LastAccessDate) AS LastAccess,
    MIN(p.CreationDate) AS FirstPostDate,
    MAX(p.LastActivityDate) AS LastActivityDate,
    COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.UserId ELSE NULL END) AS TotalBadges,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS FirstClosedDate,
    STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) AS Tags,
    MAX(p.ViewCount) AS MaxViews,
    MIN(p.ViewCount) AS MinViews
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
INNER JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Tags t ON p.Id IN (t.ExcerptPostId, t.WikiPostId)
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= DATEADD(year, -5, GETDATE())
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
GROUP BY 
    u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
