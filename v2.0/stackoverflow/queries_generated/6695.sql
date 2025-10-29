-- {"query": "6695.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 644} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswersToQuestions,
    MAX(u.LastAccessDate) AS LastAccess,
    MIN(p.CreationDate) AS FirstPost,
    MAX(p.LastActivityDate) AS LastActivity,
    b.Class,
    t.TagName,
    ph.RevisionGUID,
    ph.Comment,
    ph.CreationDate AS LastEditDate,
    v.VoteTypeId,
    vl.BountyAmount
FROM 
    Users u
LEFT JOIN 
    (SELECT 
         UserId, 
         MAX(Case When PostHistoryTypeId = 1 THEN CreationDate END) AS LastEditDate
     FROM 
         PostHistory 
     GROUP BY 
         UserId) ph ON u.Id = ph.UserId
LEFT JOIN 
    (SELECT 
         Id, 
         MAX(Case When PostHistoryTypeId = 1 THEN RevisionGUID END) AS RevisionGUID,
         MAX(Case When PostHistoryTypeId = 1 THEN Comment END) AS Comment
     FROM 
         PostHistory 
     GROUP BY 
         Id) ph_latest ON u.Id = ph_latest.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         Id, 
         TagName, 
         COUNT(*) AS Count
     FROM 
         Tags 
     GROUP BY 
         Id, TagName) t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    (SELECT 
         PostId, 
         BountyAmount
     FROM 
         Votes 
     WHERE 
         VoteTypeId = 8) vl ON p.Id = vl.PostId
WHERE 
    u.Reputation > 1000
    AND p.PostTypeId IN (1, 2)
    AND (u.LastAccessDate > DATEADD(month, -6, GETDATE()) OR u.LastAccessDate IS NULL)
GROUP BY 
    u.DisplayName, u.Reputation, b.Class, t.TagName, ph.RevisionGUID, ph.Comment, ph_latest.RevisionGUID, v.VoteTypeId, vl.BountyAmount
ORDER BY 
    u.Reputation DESC, TotalPosts DESC;
