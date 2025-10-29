-- {"query": "6471.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 462}
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    AVG(p.Score) AS AvgPostScore,
    MAX(ph.CreationDate) AS LatestPostHistory,
    SUM(CASE WHEN v_up.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN v_down.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
    STRING_AGG(DISTINCT t.TagName, ', ') AS TaggedWith,
    SUM(CASE WHEN pl_link.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostsCount,
    SUM(CASE WHEN pl_dup.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostsCount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN
    Votes v_up ON v_up.PostId = p.Id AND v_up.VoteTypeId = 2
LEFT JOIN
    Votes v_down ON v_down.PostId = p.Id AND v_down.VoteTypeId = 3
LEFT JOIN
    Posts pp_tags ON pp_tags.Id = p.Id
LEFT JOIN
    Tags t ON t.ExcerptPostId = pp_tags.Id
LEFT JOIN
    PostLinks pl_link ON pl_link.PostId = p.Id AND pl_link.LinkTypeId = 1
LEFT JOIN
    PostLinks pl_dup ON pl_dup.PostId = p.Id AND pl_dup.LinkTypeId = 3
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalPosts DESC;