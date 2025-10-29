-- {"query": "6690.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 518} 

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
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedDate,
    STRING_AGG(t.TagName, ', ') AS MostCommonTags
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         UserId, 
         Max(CreationDate) AS LastVoteDate
     FROM 
         Votes 
     GROUP BY 
         UserId) v ON u.Id = v.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (SELECT 
         UserId, 
         PostId, 
         VoteTypeId 
     FROM 
         Votes 
     WHERE 
         CreationDate = (SELECT MAX(CreationDate) FROM Votes WHERE UserId = v.UserId)) v2 ON u.Id = v2.UserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN 
    (SELECT 
         Id, 
         STRING_AGG(TagName, ', ') AS TagName 
     FROM 
         Tags 
     GROUP BY 
         Id) t ON p.Id = t.Id
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= DATEADD(year, -5, GETDATE())
GROUP BY 
    u.DisplayName, 
    u.Reputation, 
    b.Name, 
    v.Name
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    AVG(p.ViewCount) DESC, 
    u.Reputation DESC;
