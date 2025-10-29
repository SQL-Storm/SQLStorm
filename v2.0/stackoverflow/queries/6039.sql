SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.AnswerCount,0) ELSE 0 END) AS TotalAnswersToQuestions,
    MAX(u.LastAccessDate) AS LastAccessDate,
    MAX(p.LastActivityDate) AS LastActivePostDate,
    b.Name AS LatestBadge,
    b.Date AS BadgeDate,
    rnph.Comment AS LatestPostHistoryComment,
    rnph.CreationDate AS LatestPostHistoryDate
FROM 
    Users u
LEFT JOIN 
    (
      SELECT 
         ph.UserId, 
         ph.PostId, 
         ph.Comment, 
         ph.CreationDate,
         ROW_NUMBER() OVER(PARTITION BY ph.UserId ORDER BY ph.CreationDate DESC) AS rn
      FROM 
         PostHistory ph
      WHERE 
         ph.PostHistoryTypeId IN (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,19,20,35,36,50,52,53,66)
    ) rnph
     ON u.Id = rnph.UserId AND rnph.rn = 1
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (
      SELECT 
         b2.UserId, 
         MAX(b2.Date) AS MaxBadgeDate
      FROM 
         Badges b2
      GROUP BY 
         b2.UserId
    ) mb
     ON u.Id = mb.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
WHERE 
    (u.Reputation > 10000 OR u.Reputation IS NULL) 
    AND (p.LastActivityDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY OR p.LastActivityDate IS NULL)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Name, b.Date, rnph.Comment, rnph.CreationDate
HAVING 
    COUNT(DISTINCT p.Id) > 50 
    AND AVG(p.Score) > 100
ORDER BY 
    TotalScore DESC, 
    BadgeDate DESC;