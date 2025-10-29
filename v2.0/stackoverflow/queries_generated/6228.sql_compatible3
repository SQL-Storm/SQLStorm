SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswersToQuestions,
    MAX(u.LastAccessDate) AS LastAccessDate,
    b.Class,
    t.TagNames,
    ph.RevisionGUID,
    ph.LastEditDate
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (
      SELECT 
         ph_inner.UserId,
         ph_inner.PostId,
         ph_inner.RevisionGUID,
         ph_inner.CreationDate AS LastEditDate,
         ROW_NUMBER() OVER (PARTITION BY ph_inner.UserId ORDER BY ph_inner.CreationDate DESC) AS rn
      FROM 
         PostHistory ph_inner
      WHERE 
         ph_inner.PostHistoryTypeId IN (2, 5, 6)
    ) ph ON ph.UserId = u.Id AND ph.rn = 1
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (
     SELECT 
         PostId,
         STRING_AGG(TagName, ', ') AS TagNames
     FROM 
         Tags
     GROUP BY 
         PostId
    ) t ON t.PostId = p.Id
WHERE 
    u.Reputation > 10000
    AND p.PostTypeId IN (1, 2)
    AND EXISTS (
        SELECT 1 
        FROM 
            Votes v 
        WHERE 
            v.PostId = p.Id 
            AND v.VoteTypeId = 2
    )
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.LastAccessDate, b.Class, t.TagNames, ph.RevisionGUID, ph.LastEditDate
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 5
ORDER BY 
    TotalScore DESC, 
    u.Reputation DESC;