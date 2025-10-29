-- {"query": "6028.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 496} 

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
    MAX(p.LastActivityDate) AS LastActivity,
    b.Class,
    b.TagBased,
    COALESCE(SUM(v.BountyAmount), 0) AS TotalBounties,
    STRING_AGG(DISTINCT t.TagName, ', ') AS PopularTags
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         ph.PostId, 
         ph.RevisionGUID,
         ph.CreationDate,
         ph.UserId,
         ph.UserDisplayName,
         SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS BountyAmount
     FROM 
         PostHistory ph
     LEFT JOIN 
         Votes v ON ph.PostId = v.PostId AND v.VoteTypeId = 8
     GROUP BY 
         ph.PostId, ph.RevisionGUID, ph.CreationDate, ph.UserId, ph.UserDisplayName) v ON u.Id = v.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    p.CreationDate >= DATEADD(year, -5, GETDATE())
GROUP BY 
    u.DisplayName, u.Reputation, b.Class, b.TagBased
HAVING 
    SUM(p.Score) > 1000
ORDER BY 
    TotalPosts DESC, TotalScore DESC;
