SELECT 
    u.DisplayName,
    u.Id,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionsScore,
    MAX(p.LastActivityDate) AS LastActivePost,
    b.Name AS LatestBadge,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY MAX(p.LastActivityDate) DESC) AS RecentActivityRank
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (
      SELECT 
         p.OwnerUserId,
         MAX(ph.CreationDate) AS LastEditDate
      FROM 
         Posts p
      JOIN 
         PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 5
      GROUP BY 
         p.OwnerUserId
    ) AS p_latest ON u.Id = p_latest.OwnerUserId
LEFT JOIN 
    Votes v ON u.Id = v.UserId
LEFT JOIN 
    Posts p ON v.PostId = p.Id
WHERE 
    u.Reputation >= 1000
    AND p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
    AND (u.Location IS NOT NULL OR u.WebsiteUrl IS NOT NULL)
GROUP BY 
    u.DisplayName,
    u.Id,
    b.Name
HAVING 
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) > 2
ORDER BY 
    TotalVotes DESC, 
    RecentActivityRank ASC;