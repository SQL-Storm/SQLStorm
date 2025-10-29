-- {"query": "6626.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 494} 
SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN p.Id END) AS TotalDuplicates,
    MAX(u.CreationDate) AS LastAccountActivity,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastPostClosed,
    MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS LastPostReopened,
    AVG(p.Score) AS AvgPostScore
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    (SELECT 
        Id, 
        MAX(CASE WHEN PostHistoryTypeId IN (10, 11, 12, 13) THEN CreationDate END) AS RecentHistory
     FROM 
        PostHistory
     GROUP BY 
        Id) ph2 ON p.Id = ph2.Id
WHERE 
    u.Reputation > 1000
    AND (u.Id NOT IN (SELECT UserId FROM Comments WHERE Text LIKE '%spam%') OR u.Id IS NULL)
    AND (b.Id IS NULL OR b.Date >= '2022-01-01')
    AND (ph2.RecentHistory IS NULL OR ph2.RecentHistory > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 month')
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;