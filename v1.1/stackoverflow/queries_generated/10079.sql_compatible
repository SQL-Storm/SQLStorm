SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId ELSE NULL END) AS TotalDownVotes,
    MAX(p.MaxScore) AS HighestScoredPost,
    AVG(p.AvgScore) AS AverageScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END), 0) AS TotalAnswersToQuestions,
    MIN(ph.CreationDate) AS FirstPostEdit,
    MAX(ph.CreationDate) AS LastPostEdit,
    MIN(c.CreationDate) AS FirstComment,
    MAX(c.CreationDate) AS LastComment,
    b.Class AS BadgeClass,
    b.TagBased
FROM 
    Users u
LEFT JOIN 
    (SELECT 
         ph.PostId, 
         MIN(ph.CreationDate) AS CreationDate
     FROM 
         PostHistory ph
     WHERE 
         ph.PostHistoryTypeId IN (1, 2, 4, 5, 6, 10, 11, 12, 13, 14, 15, 19, 20, 35)
     GROUP BY 
         ph.PostId) ph ON u.Id = ph.PostId
LEFT JOIN 
    (SELECT 
         c.UserId,
         MIN(c.CreationDate) AS CreationDate
     FROM 
         Comments c
     GROUP BY 
         c.UserId) c ON u.Id = c.UserId
LEFT JOIN 
    (SELECT 
         p.OwnerUserId, 
         COUNT(DISTINCT p.Id) AS AnswerCount,
         MAX(p.Score) AS MaxScore,
         AVG(p.Score) AS AvgScore,
         MAX(p.PostTypeId) FILTER (WHERE true) AS PostTypeId,
         MAX(p.Id) FILTER (WHERE true) AS Id
     FROM 
         Posts p
     GROUP BY 
         p.OwnerUserId
    ) p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON u.Id = v.UserId
LEFT JOIN 
    (SELECT 
         b.UserId, 
         MIN(b.Class) AS Class,
         b.TagBased
     FROM 
         Badges b
     GROUP BY 
         b.UserId, b.TagBased
    ) b ON u.Id = b.UserId
WHERE 
    u.Reputation > 1000
    AND u.LastAccessDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location, b.Class, b.TagBased
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 5
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;