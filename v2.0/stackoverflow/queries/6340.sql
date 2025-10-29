-- {"query": "6340.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 365}
SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.AboutMe,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId ELSE NULL END) AS TotalDownVotes,
    MAX(u.CreationDate) AS LatestAccountActivity,
    STRING_AGG(DISTINCT t.TagName, ', ') AS PopularTags,
    MAX(ph.RevisionGUID) AS LastRevisionGUID
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
    u.Reputation > 100
    AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1' YEAR)
GROUP BY 
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.AboutMe
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalUpVotes DESC, 
    TotalPosts DESC
LIMIT 100;