SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId ELSE NULL END) AS TotalDownVotes,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MIN(ph.CreationDate) AS FirstPostEdit,
    MAX(ph.CreationDate) AS LastPostEdit,
    b.Name AS LatestBadgeEarned,
    rn.TopScoredPostRank,
    avg_per_user.AvgScorePerUser
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN (
    SELECT OwnerUserId, ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY Score DESC, Id) AS TopScoredPostRank, Id AS PostId
    FROM Posts
) rn ON rn.OwnerUserId = u.Id AND rn.PostId = p.Id
LEFT JOIN (
    SELECT OwnerUserId, AVG(Score) AS AvgScorePerUser
    FROM Posts
    GROUP BY OwnerUserId
) avg_per_user ON avg_per_user.OwnerUserId = u.Id
WHERE 
    u.Reputation > 10000
    AND (u.Id, b.Date) IN (
        SELECT UserId, MAX(Date) 
        FROM Badges 
        GROUP BY UserId
    )
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Name, rn.TopScoredPostRank, avg_per_user.AvgScorePerUser
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, TotalPosts DESC
LIMIT 100;