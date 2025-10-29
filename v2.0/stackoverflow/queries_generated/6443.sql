-- {"query": "6443.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 500} 

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
    (SELECT 
         ph.PostId, 
         ph.Comment, 
         ph.CreationDate AS LastEditDate
     FROM 
         PostHistory ph
     WHERE 
         ph.PostHistoryTypeId = 5
     GROUP BY 
         ph.PostId
     ORDER BY 
         ph.LastEditDate DESC
     LIMIT 100) ph ON u.Id = ph.PostId
LEFT JOIN 
    (SELECT 
         u.Id AS UserId, 
         b.Id AS BadgeId, 
         b.Date AS BadgeDate
     FROM 
         Badges b
     JOIN Users u ON b.UserId = u.Id
     WHERE 
         b.Class = 1
     ORDER BY 
         b.Date DESC
     LIMIT 100) b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         pv.PostId, 
         pv.VoteTypeId, 
         pv.CreationDate AS VoteDate
     FROM 
         Votes pv
     WHERE 
         pv.VoteTypeId != 6
     ORDER BY 
         pv.CreationDate DESC
     LIMIT 100) v ON u.Id = v.UserId
JOIN 
    Posts p ON u.Id = p.OwnerUserId
WHERE 
    p.LastActivityDate > p.CreationDate
GROUP BY 
    u.Id
HAVING 
    COUNT(p.Id) > 10 
    AND AVG(p.Score) > 100
ORDER BY 
    TotalPosts DESC, 
    HighestScoredPost DESC;
