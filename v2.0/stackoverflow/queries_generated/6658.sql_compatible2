SELECT 
    u.Id,
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    AVG(p.Score) AS AvgScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswers,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedDate,
    b.Name AS LatestBadge,
    ROW_NUMBER() OVER(PARTITION BY u.Id ORDER BY MAX(p.LastActivityDate) DESC) AS RecencyRank
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN 
    (
      SELECT UserId, Name, Date FROM Badges
    ) b ON u.Id = b.UserId AND b.Date = (
        SELECT MAX(b2.Date) FROM Badges b2 WHERE b2.UserId = u.Id
    )
WHERE 
    u.Reputation > 1000
    AND p.PostTypeId IN (1, 2)
    AND p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
GROUP BY 
    u.Id,
    u.DisplayName,
    b.Name
HAVING 
    AVG(p.Score) > 10
ORDER BY 
    TotalPosts DESC, 
    AvgScore DESC;