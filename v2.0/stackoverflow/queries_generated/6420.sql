-- {"query": "6420.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 435} 

SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.CreationDate) AS FirstPostDate,
    MAX(p.LastActivityDate) AS LastActiveDate,
    b.Name AS MostRecentBadge,
    b.Date AS BadgeEarnedDate
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
    AND b.Date = (SELECT MAX(Date) FROM Badges WHERE UserId = u.Id)
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON u.Id = v.UserId
WHERE 
    u.Reputation > 10000
    AND p.LastActivityDate > (CURRENT_TIMESTAMP - INTERVAL '1 year')
    AND EXISTS (
        SELECT 1
        FROM Comments c
        WHERE c.PostId = p.Id
        AND c.Text LIKE '%thank you%'
        AND c.CreationDate < p.LastActivityDate
    )
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location
HAVING 
    COUNT(DISTINCT v.PostId) > 100
ORDER BY 
    TotalPosts DESC, HighestScoredPost DESC
LIMIT 100;
