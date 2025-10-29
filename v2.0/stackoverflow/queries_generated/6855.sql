-- {"query": "6855.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 435} 

SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(ph.CreationDate) AS LatestPostEdit,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId END) AS TotalDownVotes,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.ClosedDate IS NOT NULL) AS TotalClosedPosts,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.CommunityOwnedDate IS NOT NULL) AS TotalCommunityOwnedPosts,
    MAX(p.LastActivityDate) AS MostRecentPostActivity,
    MIN(p.CreationDate) AS EarliestPost,
    AVG(p.Score) AS AvgPostScore,
    STRING_AGG(DISTINCT t.TagName, ', ') WITHIN GROUP AS ORDER BY t.TagName AS MostCommonTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
    AND (u.Location IS NOT NULL OR u.DisplayName IS NOT NULL)
GROUP BY 
    u.Id
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalPosts DESC, 
    AvgPostScore DESC
LIMIT 10;
