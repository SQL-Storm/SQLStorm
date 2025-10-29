-- {"query": "6422.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 589} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalScore,
    MAX(p.LastActivityDate) AS LastActivePost,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.LastEditDate ELSE NULL END) AS LastEditedQuestion,
    MIN(p.CreationDate) AS FirstPost,
    MAX(p.CreationDate) AS LastPost,
    b.Name,
    b.Class,
    l.Name AS LinkType,
    v.Name AS VoteType,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId ELSE NULL END) AS DuplicateLinks,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId ELSE NULL END) AS LinkedPosts,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.PostId ELSE NULL END) AS LinkedToPosts,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.PostId ELSE NULL END) AS DuplicateOfPosts
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkType
     FROM 
        PostLinks pl
     JOIN 
        LinkTypes lt ON pl.LinkTypeId = lt.Id) pl ON u.Id = pl.PostId
LEFT JOIN 
    (SELECT 
        pv.PostId, 
        vt.Name AS VoteType,
        pv.BountyAmount
     FROM 
        Votes pv
     JOIN 
        VoteTypes vt ON pv.VoteTypeId = vt.Id) v ON u.Id = v.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
WHERE 
    (u.Reputation > 1000 OR u.Reputation IS NULL)
    AND (p.Score > 0 OR p.PostTypeId = 6)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Id, b.Name, b.Class
HAVING 
    COUNT(DISTINCT p.Id) > 5
ORDER BY 
    TotalScore DESC, 
    TotalPosts DESC;
