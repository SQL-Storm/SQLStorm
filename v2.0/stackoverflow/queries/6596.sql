SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotes,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.LastActivityDate) AS FirstActivityDate,
    b.Name AS LatestBadge,
    c.Text AS LastComment,
    COALESCE(MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END), 'No Close Reason') AS CloseReason
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Comments c ON u.Id = c.UserId AND c.CreationDate = (
        SELECT MAX(CreationDate) FROM Comments WHERE UserId = u.Id
    )
LEFT JOIN 
    Votes v ON u.Id = v.UserId
LEFT JOIN 
    Posts p ON v.PostId = p.Id
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
WHERE 
    u.Reputation > 1000
    AND p.PostTypeId = 1
    AND p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Name, c.Text
HAVING 
    COUNT(DISTINCT v.PostId) > 50
ORDER BY 
    u.Reputation DESC, TotalVotes DESC
LIMIT 100;