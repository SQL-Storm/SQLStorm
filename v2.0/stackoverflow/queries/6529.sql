-- {"query": "6529.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 498}
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
    SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostsCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS CommonTags,
    MAX(ph.CreationDate) AS LastPostEdit,
    AVG(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400.0) AS AvgDaysToLastActivity
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 10000
    AND u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months')
    AND (p.PostTypeId IN (1, 2) OR p.AnswerCount > 0)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalPosts DESC, HighestScoredPost DESC;