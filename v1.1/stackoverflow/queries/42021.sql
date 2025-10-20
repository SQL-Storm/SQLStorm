-- {"query": "42021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 516} 
SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    u.DisplayName AS OwnerDisplayName, 
    u.Reputation, 
    COUNT(v.Id) AS TotalVotes,
    COUNT(DISTINCT ph.UserId) AS UniqueEditors,
    COUNT(DISTINCT c.Id) AS TotalComments,
    AVG(LENGTH(ph.Text)) AS AvgPostHistoryTextLength,
    MAX(ph.CreationDate) AS LastEditDate,
    MIN(ph.CreationDate) AS FirstEditDate,
    COUNT(DISTINCT ph.PostHistoryTypeId) AS UniqueEditTypes,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35) THEN ph.Id END) AS SignificantEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN ph.Id END) AS BodyEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 4) THEN ph.Id END) AS TitleEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (3, 6) THEN ph.Id END) AS TagEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN ph.Id END) AS Rollbacks
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
WHERE 
    p.PostTypeId = 1
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, u.DisplayName, u.Reputation
HAVING 
    COUNT(v.Id) > 10
    AND COUNT(DISTINCT ph.UserId) > 3
ORDER BY 
    p.Score DESC, 
    COUNT(v.Id) DESC, 
    COUNT(DISTINCT ph.UserId) DESC
LIMIT 100;