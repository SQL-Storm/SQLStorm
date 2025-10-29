-- {"query": "6791.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 425} 

SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    COUNT(DISTINCT c.PostId) AS TotalComments,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS HighestScoredQuestion,
    MIN(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS LowestViewedQuestion,
    MAX(ph.CreationDate) AS LastActivity,
    b.Name AS LatestBadge,
    b.Date AS BadgeDate,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.LastActivityDate DESC) AS RecentActivityRank
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 10000
    AND u.LastAccessDate > (CURRENT_DATE - INTERVAL '1 year')
    AND p.PostTypeId IN (1, 2)
    AND (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 2) > 5
    AND (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 3) < 2
GROUP BY 
    u.Id, b.Id
HAVING 
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) > 1000
ORDER BY 
    RecentActivityRank ASC, u.Reputation DESC;
