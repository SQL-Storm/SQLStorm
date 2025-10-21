-- {"query": "32069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 239} 
SELECT 
    u.DisplayName, 
    p.Title, 
    COUNT(v.Id) AS TotalVotes, 
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS TotalComments,
    (SELECT STRING_AGG(t.TagName, ', ') 
     FROM Tags t 
     WHERE ',' || p.Tags || ',' LIKE '%<' || t.TagName || '>%') AS Tags,
    EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 3600 AS ActiveDurationInHours
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON v.PostId = p.Id
WHERE 
    p.PostTypeId = 1 
    AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    AND u.Reputation > 1000
GROUP BY 
    u.DisplayName, p.Title, p.Id, p.CreationDate, p.LastActivityDate, p.Tags
HAVING 
    COUNT(v.Id) > 50
ORDER BY 
    TotalVotes DESC
LIMIT 30;