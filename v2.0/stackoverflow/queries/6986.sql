SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId ELSE NULL END) AS TotalDownVotes,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestUserCreationDate,
    STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) AS Tags,
    (
        SELECT 
            COUNT(DISTINCT pl2.RelatedPostId) 
        FROM 
            PostLinks pl2
        WHERE 
            pl2.PostId = p.Id AND pl2.LinkTypeId = 3
    ) AS DuplicateCount,
    (
        SELECT 
            MAX(ph2.CreationDate)
        FROM 
            PostHistory ph2
        WHERE 
            ph2.PostId = p.Id AND ph2.PostHistoryTypeId = 10
    ) AS LastClosedDate
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Id IN (
        SELECT 
            UserId 
        FROM 
            Badges 
        WHERE 
            Class = 1
    )
GROUP BY 
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    p.Id
HAVING 
    COUNT(DISTINCT p.Id) > 10 
    AND COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) > COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId ELSE NULL END)
ORDER BY 
    MaxReputation DESC, 
    EarliestUserCreationDate ASC;