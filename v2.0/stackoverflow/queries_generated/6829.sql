-- {"query": "6829.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 500} 

SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.CreationDate) AS FirstPost,
    MAX(p.LastActivityDate) AS LastActivity,
    b.Name AS LatestBadge,
    ph.Comment AS LastEditComment,
    v.VoteTypeId AS LastVoteType
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         UserId, 
         MAX(Date) AS MaxBadgeDate
     FROM 
         Badges
     GROUP BY 
         UserId) bb ON u.Id = bb.UserId AND b.Date = bb.MaxBadgeDate
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (SELECT 
         PostId, 
         MAX(CreationDate) AS MaxEditDate
     FROM 
         PostHistory
     WHERE 
         PostHistoryTypeId = 5 -- Edit Body
     GROUP BY 
         PostId) ph ON p.Id = ph.PostId
LEFT JOIN 
    PostHistory ph2 ON p.Id = ph2.PostId AND ph2.CreationDate = ph.MaxEditDate
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.CreationDate = 
    (SELECT 
         MAX(CreationDate) 
     FROM 
         Votes 
     WHERE 
         PostId = p.Id) 
WHERE 
    u.Id IN 
    (SELECT 
         UserId 
     FROM 
         Votes 
     WHERE 
         VoteTypeId IN (2, 3) 
     GROUP BY 
         UserId 
     HAVING 
         COUNT(DISTINCT PostId) > 10)
AND 
    u.Reputation > 1000
GROUP BY 
    u.DisplayName, u.Reputation
HAVING 
    COUNT(p.Id) > 50
ORDER BY 
    HighestScoredPost DESC;
