SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location,
    b.Id AS BadgeId,
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(p.Score) AS TotalScore,
    MAX(p.LastActivityDate) AS LastActivity,
    MIN(p.CreationDate) AS FirstPost,
    MAX(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.ViewCount,0) ELSE 0 END) AS MaxQuestionViewCount,
    MAX(CASE WHEN p.PostTypeId = 2 THEN COALESCE(p.ViewCount,0) ELSE 0 END) AS MaxAnswerViewCount,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 1 THEN v.PostId ELSE NULL END) AS AcceptedAnswerCount,
    COUNT(DISTINCT CASE WHEN c.PostId IS NOT NULL THEN c.PostId ELSE NULL END) AS CommentCount,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId ELSE NULL END) AS LinkedPostCount,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId ELSE NULL END) AS DuplicatePostCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    (u.Reputation > 10000 OR u.Reputation IS NULL)
    AND (p.Score > 0 OR p.Score IS NULL)
    AND (v.VoteTypeId IN (1, 2, 3) OR v.VoteTypeId IS NULL)
    AND (c.Text LIKE '%thank you%' OR c.Text IS NULL)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location, b.Id, b.Name, b.Date
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    TotalScore DESC, 
    BadgeDate DESC
LIMIT 100;