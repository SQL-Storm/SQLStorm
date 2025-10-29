-- {"query": "6517.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 388}
SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
    MAX(u.LastAccessDate) AS LastAccessDate,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    ROW_NUMBER() OVER(PARTITION BY u.Id ORDER BY MAX(u.LastAccessDate) DESC) AS RankByLastAccess
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         ph.PostId, 
         MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS CloseReason,
         MAX(CASE WHEN ph.PostHistoryTypeId = 101 THEN ph.Text ELSE NULL END) AS DuplicateReason
     FROM 
         PostHistory ph
     GROUP BY 
         ph.PostId) ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 1000
    AND p.PostTypeId IN (1, 2)
    AND (p.ClosedDate IS NULL OR p.ClosedDate < (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY))
    AND (ph.CloseReason IS NULL OR ph.CloseReason NOT IN ('Duplicate', 'Off-topic'))
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalQuestionScore DESC, 
    RankByLastAccess ASC
LIMIT 100;