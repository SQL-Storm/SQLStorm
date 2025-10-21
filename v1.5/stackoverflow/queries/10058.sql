SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.CreationDate) AS FirstPostDate,
    MAX(p.LastActivityDate) AS LastActivityDate,
    b.Name AS LatestBadge,
    SUBSTR(p.Tags, 1, POSITION(',' IN p.Tags) - 1) AS MostFrequentTag
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON u.Id = v.UserId
WHERE 
    u.Reputation > 1000 AND 
    p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
GROUP BY 
    u.DisplayName,
    u.Reputation,
    b.Name,
    SUBSTR(p.Tags, 1, POSITION(',' IN p.Tags) - 1)
HAVING 
    AVG(p.Score) > 10
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC
LIMIT 100;