-- {"query": "10033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 429} 

SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN p.ViewCount > 1000 THEN 1 ELSE 0 END) AS PopularPosts,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    MAX(b.Date) AS LastBadgeEarned,
    ph.Comment AS LastEditComment,
    ph.PostId
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (SELECT 
        PostId, 
        Comment, 
        ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CreationDate DESC) AS rn
     FROM 
        PostHistory
     WHERE 
        PostHistoryTypeId IN (1, 2, 5, 6, 7, 10, 11, 12, 13, 14, 15, 19, 20, 35)
    ) ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= DATEADD(year, -2, CURRENT_TIMESTAMP)
    AND (p.Score > 0 OR p.PostTypeId IN (1, 2))
GROUP BY 
    u.DisplayName, ph.PostId
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 1
ORDER BY 
    TotalPosts DESC, 
    TotalQuestions DESC;
