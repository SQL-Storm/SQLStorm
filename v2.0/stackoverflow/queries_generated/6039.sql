-- {"query": "6039.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 633} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswersToQuestions,
    MAX(u.LastAccessDate) AS LastAccessDate,
    MAX(p.LastActivityDate) AS LastActivePostDate,
    b.Name AS LatestBadge,
    b.Date AS BadgeDate,
    ph.Comment AS LatestPostHistoryComment,
    ph.CreationDate AS LatestPostHistoryDate
FROM 
    Users u
LEFT JOIN 
    (SELECT 
         ph.UserId, 
         ph.PostId, 
         ph.Comment, 
         ph.CreationDate,
         ROW_NUMBER() OVER(PARTITION BY ph.UserId ORDER BY ph.CreationDate DESC) AS rn
     FROM 
         PostHistory ph
     WHERE 
         ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 19, 20, 35, 36, 50, 52, 53, 66)) AS rnph
     ON u.Id = rnph.UserId AND rnph.rn = 1
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         b.UserId, 
         MAX(b.Date) AS MaxBadgeDate
     FROM 
         Badges b
     GROUP BY 
         b.UserId) AS mb
     ON u.Id = mb.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
WHERE 
    (u.Reputation > 10000 OR u.Reputation IS NULL) 
    AND (p.LastActivityDate >= DATEADD(day, -30, CURRENT_TIMESTAMP) OR p.LastActivityDate IS NULL)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Name, b.Date, ph.Comment, ph.CreationDate
HAVING 
    COUNT(DISTINCT p.Id) > 50 
    AND AVG(p.Score) > 100
ORDER BY 
    TotalScore DESC, 
    LatestBadgeDate DESC;
