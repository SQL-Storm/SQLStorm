-- {"query": "6424.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 468} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LastPostActivity,
    SUM(v.BountyAmount) AS TotalBountyPoints,
    MAX(ph.RevisionGUID) AS LastRevisionGUID,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.LastActivityDate DESC) AS MostActivePost,
    (
        SELECT STRING_AGG(tg.TagName, ', ')
        FROM Tags tg
        WHERE tg.Id IN (
            SELECT DISTINCT Tags::text[]->>0
            FROM Posts
            WHERE Posts.Id = p.Id
        )
    ) AS TagsUsed,
    (
        SELECT COUNT(*) 
        FROM PostLinks pl 
        WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
    ) AS DuplicateCount,
    (
        SELECT COUNT(DISTINCT b.Id)
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 1
    ) AS GoldBadgeCount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 10000
    AND p.LastEditDate > (
        SELECT MAX(LastEditDate) 
        FROM Posts 
        WHERE PostTypeId = 1
    )
GROUP BY 
    u.Id
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    TotalBountyPoints DESC, 
    TotalPosts DESC
LIMIT 100;
