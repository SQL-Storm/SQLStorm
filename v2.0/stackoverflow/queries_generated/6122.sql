-- {"query": "6122.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 450} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LastPostActivity,
    b.Name AS LatestBadge,
    ph.Comment AS LatestPostHistory,
    v.VoteTypeId AS LatestVoteType
FROM 
    Users u
LEFT JOIN 
    (SELECT 
         UserId, 
         MAX(Date) AS MaxBadgeDate
     FROM 
         Badges
     GROUP BY 
         UserId) b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         PostId, 
         MAX(CreationDate) AS MaxPostHistoryDate, 
         Comment
     FROM 
         PostHistory
     GROUP BY 
         PostId) ph ON p.Id = ph.PostId
LEFT JOIN 
    (SELECT 
         PostId, 
         MAX(CreationDate) AS MaxVoteDate, 
         VoteTypeId
     FROM 
         Votes
     GROUP BY 
         PostId) v ON p.Id = v.PostId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
WHERE 
    u.Reputation > 1000
    AND p.LastActivityDate > (CURRENT_DATE - INTERVAL '1 year')
    AND EXISTS (
        SELECT 1 
        FROM Comments c 
        WHERE c.PostId = p.Id 
        AND c.Score > 0
    )
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 5
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC
LIMIT 100;
