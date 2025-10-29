-- {"query": "6566.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 336} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    MAX(b.Date) AS LastBadgeEarned,
    MAX(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Score END) AS HighestAcceptedAnswerScore,
    STRING_AGG(DISTINCT t.TagName, ', ') AS PopularTags,
    GROUP_CONCAT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN p.Title END ORDER BY pl.CreationDate DESC SEPARATOR ', ') AS Duplicates
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 YEAR)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
ORDER BY 
    TotalPosts DESC, TotalVotes DESC
LIMIT 100;
