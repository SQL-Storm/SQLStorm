-- {"query": "6659.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 438} 

SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId ELSE NULL END) AS TotalDownVotes,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.CreationDate) AS FirstPostDate,
    MAX(p.LastActivityDate) AS LastActivityDate,
    AVG(p.ViewCount) AS AvgViewCount,
    MAX(b.Date) AS LastBadgeEarned,
    STRING_AGG(t.TagName, ', ') AS MostCommonTags
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    (SELECT 
        pt.Id, pt.TagName, COUNT(t.Id) AS TagCount
     FROM 
        Tags t
     JOIN 
        PostTags pt ON t.Id = pt.TagId
     GROUP BY 
        pt.Id, pt.TagName
     ORDER BY 
        TagCount DESC
     ) t ON p.Id = t.Id
WHERE 
    u.Reputation > 10000
    AND p.CreationDate >= DATEADD(year, -5, GETDATE())
GROUP BY 
    u.DisplayName, u.Reputation, u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalUpVotes DESC, 
    TotalPosts DESC;
