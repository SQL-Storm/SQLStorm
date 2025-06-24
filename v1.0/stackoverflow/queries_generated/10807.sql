-- Performance Benchmarking SQL Query

-- This query benchmarks the performance by retrieving information about posts, including their associated users, tags,
-- vote counts, and comment counts, while checking for potential joins and aggregate functions that could affect performance.

SELECT 
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    u.DisplayName AS OwnerDisplayName,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags
FROM 
    Posts p
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    STRING_TO_ARRAY(p.Tags, ',') AS tag_array ON TRUE
LEFT JOIN 
    Tags t ON t.TagName = tag_array
WHERE 
    p.CreationDate >= '2023-01-01'
GROUP BY 
    p.Id, u.DisplayName
ORDER BY 
    p.CreationDate DESC
LIMIT 100;
