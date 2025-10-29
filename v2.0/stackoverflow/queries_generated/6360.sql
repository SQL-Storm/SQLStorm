-- {"query": "6360.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 403} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestCreationDate,
    MIN(p.LastActivityDate) AS EarliestPostActivity,
    b.Name AS LatestBadge,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS TopScorePost,
    (
        SELECT STRING_AGG(TagName, ', ')
        FROM Tags
        WHERE Id IN (
            SELECT TagId
            FROM PostTags
            WHERE PostId = p.Id
        )
    ) AS Tags,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (
        SELECT ph.PostId, ph.RevisionGUID, ph.CreationDate
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
    ) AS ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 1000
    AND p.Score >= 0
GROUP BY 
    u.DisplayName, u.Reputation, b.Name
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;
