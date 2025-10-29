-- {"query": "6050.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 353}
SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS HighestScoredQuestion,
    MIN(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS LowestScoredAnswer,
    SUM(v.BountyAmount) AS TotalBountyPointsEarned,
    MAX(ph.CreationDate) AS LastActivityOnAnyPost,
    (
        SELECT STRING_AGG(t.TagName, ', ')
        FROM Tags t
        WHERE t.ExcerptPostId = p.Id
    ) AS MostFrequentTags,
    COUNT(DISTINCT pl.RelatedPostId) AS TotalLinkedPosts
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
WHERE 
    u.Reputation > 10000
    AND p.LastActivityDate > (CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location,
    -- include p.Id because it's referenced in the scalar subquery and in aggregates/windows
    p.Id
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 5
ORDER BY 
    TotalPosts DESC, 
    HighestScoredQuestion DESC;