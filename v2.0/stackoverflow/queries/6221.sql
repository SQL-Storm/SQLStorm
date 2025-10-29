SELECT 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS TotalPosts, 
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestUser,
    STRING_AGG(DISTINCT b.Name, ', ') AS BadgesEarned,
    STRING_AGG(DISTINCT t.TagName, ', ') AS TagsUsed,
    MAX(v.BountyAmount) AS HighestBounty
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
WHERE 
    p.CreationDate BETWEEN (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5' YEAR) AND CAST('2024-10-01 12:34:56' AS TIMESTAMP)
    AND u.Reputation > 100
GROUP BY 
    u.DisplayName, u.Reputation, u.CreationDate
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalPosts DESC, 
    MaxReputation DESC;