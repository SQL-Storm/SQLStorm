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
    v.BountyAmount,
    c.Text AS CommentText,
    l.LinkTypeId,
    MAX(p.Score) AS MaxPostScore,
    MAX(p.LastEditDate) AS MaxPostLastEditDate
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostLinks l ON p.Id = l.PostId
WHERE 
    u.Reputation > 1000
    AND p.Score > 0
    AND p.LastEditDate > p.CreationDate
    AND (v.VoteTypeId = 2 OR v.VoteTypeId = 3)
    AND (ph.Comment IS NOT NULL OR ph.RevisionGUID IS NOT NULL)
    AND (c.Text LIKE '%bug%' OR c.Text LIKE '%feature%')
GROUP BY 
    u.DisplayName,
    u.Reputation,
    b.Class,
    t.TagName,
    ph.RevisionGUID,
    ph.Comment,
    v.VoteTypeId,
    v.BountyAmount,
    c.Text,
    l.LinkTypeId
HAVING 
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId ELSE NULL END) > COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId ELSE NULL END)
ORDER BY 
    u.Reputation DESC, MaxPostScore DESC;