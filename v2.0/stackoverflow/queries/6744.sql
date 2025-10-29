SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    b.Class,
    t.TagName,
    ph.RevisionGUID,
    ph.Comment,
    v.VoteTypeId,
    v.BountyAmount
FROM 
    Users u
LEFT JOIN 
    (
     SELECT 
         ph.PostId,
         ph.RevisionGUID,
         ph.Comment,
         CASE 
             WHEN ph.PostHistoryTypeId = 10 THEN cl.Name
             ELSE ph.Comment 
         END AS FinalComment
     FROM 
         PostHistory ph
     LEFT JOIN 
         CloseReasonTypes cl ON ph.Comment = CAST(cl.Id AS VARCHAR)
     WHERE 
         ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15, 19, 20, 33, 34, 35, 36, 50, 52, 53, 66)
    ) ph ON ph.PostId = u.Id
LEFT JOIN 
    Posts p ON p.OwnerUserId = u.Id
LEFT JOIN 
    Badges b ON b.UserId = u.Id
LEFT JOIN 
    Tags t ON t.ExcerptPostId = p.Id
LEFT JOIN 
    Votes v ON v.PostId = p.Id
WHERE 
    (u.Reputation > 1000 OR u.Reputation IS NULL)
    AND (p.Score > 100 OR p.Score IS NULL)
    AND (v.VoteTypeId IN (1, 2, 3) OR v.VoteTypeId IS NULL)
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    b.Class,
    t.TagName,
    ph.RevisionGUID,
    ph.Comment,
    v.VoteTypeId,
    v.BountyAmount
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    u.Reputation DESC,
    MAX(p.LastActivityDate) DESC;