SELECT 
    u.DisplayName,
    u.Reputation,
    COALESCE(b.BadgeCount, 0) AS TotalBadges,
    p.Score AS HighestPostScore,
    COUNT(DISTINCT c.Id) AS TotalComments,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotes,
    COUNT(DISTINCT ph.Id) AS EditCount
FROM 
    Users u
LEFT JOIN 
    (SELECT UserId, COUNT(*) AS BadgeCount FROM Badges GROUP BY UserId) b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT OwnerUserId, MAX(Score) AS Score FROM Posts GROUP BY OwnerUserId) p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments c ON u.Id = c.UserId
LEFT JOIN 
    Votes v ON u.Id = v.UserId
LEFT JOIN 
    PostHistory ph ON u.Id = ph.UserId
WHERE 
    u.CreationDate > '2022-01-01'
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, p.Score, COALESCE(b.BadgeCount, 0)
HAVING 
    COALESCE(b.BadgeCount, 0) > 5 AND COUNT(DISTINCT c.Id) > 10
ORDER BY 
    NetVotes DESC, TotalBadges DESC;