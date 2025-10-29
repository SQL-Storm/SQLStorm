SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestCreationDate,
    MIN(p.LastActivityDate) AS EarliestPostActivity,
    AVG(p.Score) AS AvgPostScore,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS CloseReason,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    (
        SELECT SUM(v.BountyAmount)
        FROM Votes v
        WHERE v.PostId = p.Id AND v.VoteTypeId = 8
    ) AS TotalBountyAmount,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 1
    ) AS TotalGoldBadges
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35)
LEFT JOIN 
    Tags t ON t.ExcerptPostId = p.Id
WHERE 
    u.Reputation > 10000
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, p.Id
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC
FETCH FIRST 100 ROWS ONLY;