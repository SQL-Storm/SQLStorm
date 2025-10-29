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
    (
     SELECT 
         ph.PostId, 
         ph.Comment, 
         ph.CreationDate AS LastEditDate
     FROM 
         PostHistory ph
     WHERE 
         ph.PostHistoryTypeId = 5
     GROUP BY 
         ph.PostId, ph.Comment, ph.CreationDate
     ORDER BY 
         ph.CreationDate DESC
     FETCH FIRST 100 ROWS ONLY
    ) ph ON u.Id = ph.PostId
LEFT JOIN 
    (
     SELECT 
         b.UserId AS UserId,
         b.Id AS BadgeId, 
         b.Date AS BadgeDate,
         b.Name
     FROM 
         Badges b
     JOIN Users u2 ON b.UserId = u2.Id
     WHERE 
         b.Class = 1
     ORDER BY 
         b.Date DESC
     FETCH FIRST 100 ROWS ONLY
    ) b ON u.Id = b.UserId
LEFT JOIN 
    (
     SELECT 
         pv.PostId, 
         pv.VoteTypeId, 
         pv.CreationDate AS VoteDate,
         pv.UserId
     FROM 
         Votes pv
     WHERE 
         pv.VoteTypeId != 6
     ORDER BY 
         pv.CreationDate DESC
     FETCH FIRST 100 ROWS ONLY
    ) v ON u.Id = v.UserId
JOIN 
    Posts p ON u.Id = p.OwnerUserId
WHERE 
    p.LastActivityDate > p.CreationDate
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    b.Name,
    ph.Comment,
    v.VoteTypeId
HAVING 
    COUNT(p.Id) > 10 
    AND AVG(p.Score) > 100
ORDER BY 
    TotalPosts DESC, 
    HighestScoredPost DESC;