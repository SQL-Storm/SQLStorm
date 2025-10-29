-- {"query": "6110.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 440} 

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
    CASE 
        WHEN ph.PostHistoryTypeId = 10 THEN cr.Name
        ELSE NULL
    END AS CloseReason
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    CloseReasonTypes cr ON ph.Comment = CAST(cr.Id AS varchar(10))
WHERE 
    p.CreationDate >= DATEADD(year, -5, GETDATE())
    AND u.Reputation > 1000
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
GROUP BY 
    u.DisplayName, u.Reputation, b.Class
HAVING 
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) > 10
ORDER BY 
    TotalScore DESC, 
    TotalPosts DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
