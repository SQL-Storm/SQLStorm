SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId END) AS TotalDownVotes,
    MAX(u.CreationDate) AS LatestCreationDate,
    MIN(p.LastActivityDate) AS EarliestLastActivityDate,
    b.Name AS LatestBadge,
    b.Date AS BadgeDate,
    ph.Comment AS LatestPostHistoryComment
FROM 
    Users u
LEFT JOIN 
    (SELECT 
         UserId, 
         MAX(Date) AS MaxBadgeDate
     FROM 
         Badges
     GROUP BY 
         UserId) AS b_max ON u.Id = b_max.UserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId AND b.Date = b_max.MaxBadgeDate
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    (SELECT 
         PostId, 
         MAX(CreationDate) AS MaxCreationDate
     FROM 
         PostHistory
     GROUP BY 
         PostId) AS ph_max ON p.Id = ph_max.PostId
LEFT JOIN 
    PostHistory ph ON ph.PostId = ph_max.PostId AND ph.CreationDate = ph_max.MaxCreationDate
WHERE 
    (u.Reputation > 1000 OR u.Reputation IS NULL)
    AND (p.Score > 0 OR p.Score IS NULL)
    AND (v.VoteTypeId IN (2, 3) OR v.VoteTypeId IS NULL)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Name, b.Date, ph.Comment
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    u.Reputation DESC, 
    LatestBadge DESC;