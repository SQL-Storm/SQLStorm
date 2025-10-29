-- {"query": "6991.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 289} 
SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 1 THEN p.Id END) AS TotalTitleEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 2 THEN p.Id END) AS TotalBodyEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN p.Id END) AS TotalCloses
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    (SELECT PostId, MAX(CreationDate) AS LastEditDate
     FROM PostHistory
     WHERE PostHistoryTypeId IN (1, 2, 4, 5, 6, 7)
     GROUP BY PostId) latest_edit ON p.Id = latest_edit.PostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= DATE_TRUNC('month', cast('2024-10-01' as date)) - INTERVAL '1 year'
GROUP BY 
    u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalPosts DESC
LIMIT 10;