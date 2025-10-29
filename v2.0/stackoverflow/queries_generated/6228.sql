-- {"query": "6228.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 488} 

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
    b.Class,
    t.TagName,
    ph.RevisionGUID,
    ph.CreationDate AS LastEditDate
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         ph.PostId,
         ph.RevisionGUID,
         ph.CreationDate
     FROM 
         PostHistory ph
     WHERE 
         ph.PostHistoryTypeId IN (2, 5, 6)) ph ON u.Id = ph.UserId
LEFT JOIN 
    (SELECT 
         PostId,
         STRING_AGG(TagName, ', ') AS TagNames
     FROM 
         Tags
     GROUP BY 
         PostId) t ON t.PostId = Posts.Id
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
WHERE 
    u.Reputation > 10000
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
    AND EXISTS (
        SELECT 1 
        FROM 
            Votes v 
        WHERE 
            v.PostId = p.Id 
            AND v.VoteTypeId = 2
    )
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Class
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 5
ORDER BY 
    TotalScore DESC, 
    u.Reputation DESC;
