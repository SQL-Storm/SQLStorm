SELECT 
    u.DisplayName AS UserName, 
    COUNT(DISTINCT p.Id) AS TotalPosts, 
    COUNT(DISTINCT c.Id) AS TotalComments, 
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    AVG(p.Score) AS AvgScore,
    ROUND(CAST(COUNT(DISTINCT b.Id) AS NUMERIC) / NULLIF(COUNT(DISTINCT p.Id),0), 2) AS BadgeToPostRatio,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
    COALESCE(MAX(ph.CreationDate), u.CreationDate) AS LatestActivityDate
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments c ON u.Id = c.UserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON u.Id = ph.UserId
GROUP BY 
    u.Id,
    u.DisplayName,
    u.CreationDate
HAVING 
    COUNT(DISTINCT p.Id) > 10 
    AND SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 50
ORDER BY 
    BadgeToPostRatio DESC, AvgScore DESC, UpVotesReceived DESC, LatestActivityDate DESC
LIMIT 100;