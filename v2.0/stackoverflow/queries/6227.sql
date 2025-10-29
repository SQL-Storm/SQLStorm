-- {"query": "6227.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 488}
SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) AS TotalWikis,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) AS TotalDownVotes,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.Score) AS LowestScoredPost,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS TotalClosedPosts,
    SUM(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END) AS TotalCommunityOwnedPosts,
    STRING_AGG(DISTINCT t.TagName, ', ') AS MostCommonTags,
    MAX(u.CreationDate) AS LatestUserCreationDate,
    MIN(u.LastAccessDate) AS EarliestUserLastAccessDate
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5' YEAR)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, 
    TotalViews DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;