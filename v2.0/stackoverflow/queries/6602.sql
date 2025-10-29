-- {"query": "6602.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 339}
SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    MAX(b.Date) AS LastBadgeEarned,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.LastActivityDate ELSE NULL END) AS LastQuestionActivity,
    MIN(CASE WHEN p.PostTypeId = 2 THEN p.CreationDate ELSE NULL END) AS EarliestAnswer,
    AVG(p.Score) AS AvgPostScore,
    STRING_AGG(DISTINCT t.TagName, ', ') AS PopularTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 10000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5' YEAR)
GROUP BY 
    u.DisplayName, u.Reputation, u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    AvgPostScore DESC
OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY;