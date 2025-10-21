-- {"query": "43077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 446} 

SELECT 
    u.Id AS UserId, 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(p.Score) AS TotalScore,
    AVG(p.ViewCount) AS AverageViewCount,
    MAX(p.CreationDate) AS LastPostDate,
    SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS EditCount,
    SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    COUNT(DISTINCT c.Id) AS TotalComments,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS TotalUpvotesGiven,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS TotalDownvotesGiven
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Comments c ON u.Id = c.UserId
WHERE 
    u.Reputation > 1000
GROUP BY 
    u.Id, u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalScore DESC, TotalBadges DESC
LIMIT 100;
