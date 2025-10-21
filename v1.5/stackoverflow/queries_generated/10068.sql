-- {"query": "10068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 472} 

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
    AVG(p.ViewCount) AS AvgViewsPerPost,
    STRING_AGG(DISTINCT t.TagName, ', ') AS PopularTags
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
        UserId) b2 ON b.UserId = b2.UserId AND b.Date = b2.MaxDate
LEFT JOIN 
    Votes v ON u.Id = v.UserId
LEFT JOIN 
    (SELECT 
        UserId, 
        MAX(CreationDate) AS MaxVoteDate
     FROM 
        Votes
     GROUP BY 
        UserId) v2 ON v.UserId = v2.UserId AND v.CreationDate = v2.MaxVoteDate
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (SELECT 
        PostId, 
        STRING_AGG(TagName, ', ') AS TagName
     FROM 
        Tags t
     JOIN 
        Posts pp ON t.ExcerptPostId = pp.Id
     GROUP BY 
        PostId) t ON p.Id = t.PostId
WHERE 
    u.Reputation > 100
    AND p.LastActivityDate > DATEADD(month, -6, CURRENT_TIMESTAMP)
GROUP BY 
    u.DisplayName, u.Reputation
ORDER BY 
    u.Reputation DESC;
