-- {"query": "6398.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 504} 

SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.CreationDate) AS FirstPostDate,
    MAX(p.LastActivityDate) AS LastActivityDate,
    b.Name AS LatestBadge,
    v.Name AS MostRecentVote,
    t.TagName AS MostFrequentTag
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
        UserId, 
        MAX(Date) AS MaxDate
     FROM 
        Badges
     GROUP BY 
        UserId) b2 ON u.Id = b2.UserId AND b.Date = b2.MaxDate
LEFT JOIN 
    (SELECT 
        PostId, 
        UserId, 
        MAX(CreationDate) AS MaxVoteDate
     FROM 
        Votes
     GROUP BY 
        PostId, UserId) v2 ON u.Id = v2.UserId
LEFT JOIN 
    Votes v ON v2.PostId = v.PostId AND v2.UserId = v.UserId AND v2.MaxVoteDate = v.CreationDate
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (SELECT 
        UserId, 
        TagName, 
        COUNT(*) AS TagCount
     FROM 
        Tags t
     JOIN 
        Posts pr ON t.ExcerptPostId = pr.Id
     GROUP BY 
        UserId, TagName
     ORDER BY 
        TagCount DESC
     LIMIT 1) t ON u.Id = t.UserId
WHERE 
    u.Reputation > 1000
    AND u.Id NOT IN (SELECT Id FROM Users WHERE EmailHash IS NULL)
GROUP BY 
    u.DisplayName, u.Reputation, b.Name, v.Name, t.TagName
ORDER BY 
    u.Reputation DESC, TotalPosts DESC;
