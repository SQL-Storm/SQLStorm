-- {"query": "6369.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 358} 

SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestUserCreation,
    AVG(p.Score) AS AvgPostScore,
    MAX(ph.RevisionGUID) AS LastRevisionGUID,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId ELSE NULL END) AS TotalDuplicatePosts,
    MAX(p.LastActivityDate) AS MostRecentActivity,
    STRING_AGG(DISTINCT t.TagName, ', ') WITHIN GROUP AS (ORDER BY t.Count DESC) AS TopTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Id IN (
        SELECT UserId 
        FROM Badges 
        WHERE Class = 1 AND TagBased = FALSE
    )
GROUP BY 
    u.DisplayName
HAVING 
    AVG(p.Score) > 0
ORDER BY 
    TotalPosts DESC, 
    AvgPostScore DESC;
