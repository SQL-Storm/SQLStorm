-- {"query": "6158.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 465} 

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
    CASE 
        WHEN ph.PostHistoryTypeId = 10 THEN cr.Name
        ELSE NULL
    END AS CloseReason,
    (
        SELECT STRING_AGG(vl.VoteTypeId, ', ')
        FROM Votes vl
        WHERE vl.PostId = p.Id
    ) AS VoteTypes,
    (
        SELECT COUNT(*) 
        FROM Badges bg 
        WHERE bg.UserId = u.Id AND bg.Class = 1
    ) AS GoldBadgeCount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Tags t ON (
        SELECT t.TagName 
        FROM Tags t
        WHERE t.Id = ANY (
            SELECT unnest(string_to_array(p.Tags, '/><'))
        )
    )
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    CloseReasonTypes cr ON ph.Comment = cr.Id::text
WHERE 
    p.PostTypeId IN (1, 2) AND 
    u.Reputation > 1000 AND 
    p.LastEditDate > (CURRENT_DATE - INTERVAL '1 year')
GROUP BY 
    u.Id, b.Class
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC
LIMIT 10;
