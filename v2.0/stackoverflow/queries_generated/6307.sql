-- {"query": "6307.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 436} 

SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 1 THEN p.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN p.Id END) AS TotalDuplicates,
    COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN p.Id END) AS TotalBadges,
    MAX(u.CreationDate) AS LastAccountActivity,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.LastActivityDate END) AS LastQuestionActivity,
    MAX(p.LastActivityDate) AS LastPostActivity,
    STRING_AGG(DISTINCT t.TagName, ', ') WITHIN GROUP AS DESCRIPTION AS MostFrequentTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    (SELECT PostId, COUNT(*) AS TagCount FROM Tags GROUP BY PostId HAVING COUNT(*) > 2) tg ON p.Id = tg.PostId
WHERE 
    p.PostTypeId IN (1, 2)
    AND u.Reputation > 100
    AND (u.LastAccessDate > NOW() - INTERVAL '30 days' OR u.LastAccessDate IS NULL)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
ORDER BY 
    u.Reputation DESC, TotalPosts DESC
LIMIT 100;
