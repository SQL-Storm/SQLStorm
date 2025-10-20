SELECT
    p.Id AS PostId,
    p.Title,
    u.DisplayName AS PostOwner,
    u.Reputation,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    AVG(DISTINCT v2.Score) AS AverageRelatedPostScore,
    (SELECT COUNT(*) FROM PostLinks pl2 WHERE pl2.PostId = p.Id AND pl2.LinkTypeId = 3) AS DuplicateCount,
    -- approximate median using percentile_disc on a numeric representation of CreationDate (seconds since epoch)
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM ph.CreationDate)) AS MedianEditTimeEpoch
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Posts v2 ON pl.RelatedPostId = v2.Id
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    p.PostTypeId = 1
    AND u.Reputation > 1000
    AND p.CreationDate > TIMESTAMP '2015-01-01'
GROUP BY 
    p.Id, p.Title, u.DisplayName, u.Reputation
ORDER BY 
    VoteCount DESC, Reputation DESC
LIMIT 500;