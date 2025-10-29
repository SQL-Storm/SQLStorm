-- {"query": "6478.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 508} 

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
    ph.Comment AS LastPostEditComment,
    v.VoteType
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
         ph.PostHistoryTypeId = 5 -- Edit Body
     GROUP BY 
         ph.PostId
     ORDER BY 
         ph.LastEditDate DESC
     LIMIT 100) ph ON u.Id = ph.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         p.OwnerUserId, 
         v.VoteTypeId,
         ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY v.CreationDate DESC) AS rn
     FROM 
         Posts p
     JOIN 
         Votes v ON p.Id = v.PostId
     WHERE 
         v.VoteTypeId IN (2, 3) -- UpMod, DownMod
     GROUP BY 
         p.OwnerUserId, 
         p.Id, 
         v.VoteTypeId) v ON u.Id = v.OwnerUserId AND v.rn = 1
WHERE 
    u.Id IN 
        (SELECT 
             UserId
         FROM 
             (SELECT 
                  UserId, 
                  COUNT(*) AS VoteCount
              FROM 
                  Votes
              GROUP BY 
                  UserId
              HAVING 
                  COUNT(*) > 100) sub
         WHERE 
             sub.VoteCount % 2 = 0)
GROUP BY 
    u.DisplayName, 
    u.Reputation, 
    b.Name
ORDER BY 
    TotalPosts DESC, 
    HighestScoredPost DESC;
