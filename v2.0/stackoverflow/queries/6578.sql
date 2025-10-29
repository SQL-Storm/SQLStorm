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
    ph2.Comment AS LastEditComment,
    v.VoteTypeId AS LastVoteType
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (
        SELECT 
            UserId, 
            MAX(Date) AS MaxDate
        FROM 
            Badges
        GROUP BY 
            UserId
    ) bb ON u.Id = bb.UserId AND b.Date = bb.MaxDate
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (
        SELECT 
            PostId, 
            MAX(CreationDate) AS MaxEditDate
        FROM 
            PostHistory
        WHERE 
            PostHistoryTypeId = 5
        GROUP BY 
            PostId
    ) ph ON p.Id = ph.PostId
LEFT JOIN 
    PostHistory ph2 ON p.Id = ph2.PostId AND ph2.CreationDate = ph.MaxEditDate
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.CreationDate = (
        SELECT MAX(CreationDate) FROM Votes WHERE PostId = p.Id
    )
WHERE 
    u.Reputation > 10000
    AND u.Id NOT IN (
        SELECT DISTINCT OwnerUserId 
        FROM Posts 
        WHERE PostTypeId = 3
    )
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Name, ph2.Comment, v.VoteTypeId
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 5 
    AND AVG(p.Score) > 10
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;