-- {"query": "10038.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 612} 

SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.CreationDate) AS FirstPostDate,
    MIN(p.LastActivityDate) AS LastActiveDate,
    b.Name,
    b.Class,
    v.VoteTypeId,
    v.BountyAmount,
    ph.RevisionGUID,
    ph.Comment,
    ph.CreationDate AS LastEditDate,
    c.Text AS LastComment
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
        ph.PostId, 
        ph.RevisionGUID, 
        ph.Comment, 
        ph.CreationDate 
     FROM 
        PostHistory ph
     WHERE 
        ph.PostHistoryTypeId IN (1, 2, 5, 6, 10, 11, 12, 13, 14, 15, 19, 20, 35, 36)
     ORDER BY 
        ph.CreationDate DESC
     LIMIT 1) ph ON u.Id = ph.PostId
LEFT JOIN 
    (SELECT 
        p.Id, 
        MAX(v.BountyAmount) AS BountyAmount 
     FROM 
        Posts p
     JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
     GROUP BY 
        p.Id) v ON u.Id = v.Id
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments c ON p.Id = c.PostId AND c.CreationDate = (SELECT MAX(cc.CreationDate) FROM Comments cc WHERE cc.PostId = p.Id)
WHERE 
    u.Reputation > 10000
    AND p.LastEditDate > (CURRENT_DATE - INTERVAL '1 year')
    AND EXISTS (
        SELECT 1 
        FROM 
            Votes 
        WHERE 
            PostId = p.Id 
            AND VoteTypeId IN (2, 3) 
            AND UserId != u.Id
    )
GROUP BY 
    u.Id, b.Name, b.Class, v.VoteTypeId, v.BountyAmount, ph.RevisionGUID, ph.Comment, ph.CreationDate, c.Text
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;
