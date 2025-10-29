-- {"query": "6222.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 548} 

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
    v.Name AS MostVotedType,
    t.TagName AS MostUsedTag
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         UserId, 
         Name, 
         Date 
     FROM 
         Badges 
     WHERE 
         Class = 1 
     ORDER BY 
         Date DESC 
     LIMIT 1) b1 ON u.Id = b1.UserId
LEFT JOIN 
    (SELECT 
         PostId, 
         MAX(Score) AS Name 
     FROM 
         Votes 
     GROUP BY 
         PostId) v ON p.Id = v.PostId
LEFT JOIN 
    (SELECT 
         UserId, 
         Name 
     FROM 
         VoteTypes 
     WHERE 
         Id = (SELECT 
                    MAX(Id) 
                 FROM 
                     Votes 
                 WHERE 
                     UserId = u.Id 
                 GROUP BY 
                     UserId)) vt ON vt.UserId = u.Id
LEFT JOIN 
    (SELECT 
         TagName, 
         COUNT(*) AS Count 
     FROM 
         Tags 
     GROUP BY 
         TagName 
     ORDER BY 
         Count DESC 
     LIMIT 1) t ON t.TagName IN (SELECT unnest(string_to_array(p.Tags, '/><')) 
                                 FROM 
                                     Posts p)
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
WHERE 
    u.Reputation > 1000 
    AND (u.LastAccessDate >= NOW() - INTERVAL '1 month' OR u.LastAccessDate IS NULL)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Name, vt.Name
HAVING 
    COUNT(DISTINCT p.Id) > 10 
ORDER BY 
    TotalPosts DESC, 
    HighestScoredPost DESC;
