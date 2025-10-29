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
    p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5' YEAR)
    AND u.Reputation > 1000
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
GROUP BY 
    u.DisplayName,
    u.Reputation,
    b.Class,
    t.TagName,
    ph.RevisionGUID,
    ph.PostHistoryTypeId,
    cr.Name
HAVING 
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) > 10
ORDER BY 
    TotalScore DESC, 
    TotalPosts DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;