SELECT 
    u.DisplayName,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
    MAX(p.LastActivityDate) AS LastActivePost,
    b.Name AS LatestBadge,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.LastActivityDate DESC) AS RecentActivityRank
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         ph.PostId,
         ph.CreationDate AS LastEditDate,
         ph.Text AS LastEditComment
     FROM 
         PostHistory ph
     WHERE 
         ph.PostHistoryTypeId = 11) AS ph ON u.Id = ph.PostId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 1000
    AND p.PostTypeId = 1
    AND p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
GROUP BY 
    u.DisplayName,
    b.Name,
    u.Id,
    p.LastActivityDate
HAVING 
    AVG(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 0.5
ORDER BY 
    TotalQuestionScore DESC, 
    RecentActivityRank ASC;