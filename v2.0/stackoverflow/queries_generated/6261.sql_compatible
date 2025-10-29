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
    MAX(p.LastActivityDate) AS LastActivePostDate,
    MAX(ph.CreationDate) AS LastEditedDate,
    MAX(p.ClosedDate) AS LastClosedPost,
    AVG(p.ViewCount) AS AvgViewsPerPost,
    b.Name AS LatestBadge,
    b.Date AS BadgeEarnedDate
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (
      SELECT 
         ph.PostId, 
         MAX(ph.CreationDate) AS CreationDate, 
         MAX(ph.RevisionGUID) AS MaxRevisionGUID
      FROM 
         PostHistory ph
      GROUP BY 
         ph.PostId
    ) ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Id IN (
        SELECT 
            UserId
        FROM 
            Votes
        WHERE 
            VoteTypeId IN (2, 3)
        GROUP BY 
            UserId
        HAVING 
            COUNT(DISTINCT PostId) > 10
    )
AND 
    p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6' MONTH)
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    b.Name,
    b.Date
HAVING 
    AVG(p.ViewCount) > 100
ORDER BY 
    TotalVotes DESC, 
    LatestBadge DESC;