SELECT 
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    COUNT(DISTINCT b.Id) AS BadgesEarned,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
    MAX(p.CreationDate) AS LastPostDate,
    MIN(u.CreationDate) AS UserJoinDate,
    COUNT(DISTINCT pl.Id) AS TotalLinkedPosts,
    COUNT(DISTINCT pl2.RelatedPostId) AS LinkedPostsPerQuestion,
    COUNT(DISTINCT CASE WHEN v2.VoteTypeId = (SELECT vt.Id FROM VoteTypes vt WHERE vt.Name = 'UpMod' LIMIT 1) THEN v2.Id END) AS UpVotesGiven,
    COUNT(DISTINCT CASE WHEN v3.VoteTypeId = (SELECT vt2.Id FROM VoteTypes vt2 WHERE vt2.Name = 'DownMod' LIMIT 1) THEN v3.Id END) AS DownVotesGiven,
    COUNT(DISTINCT VotesReceived.Id) AS TotalVotesReceived
FROM 
    Users u
LEFT JOIN 
    Posts p ON p.OwnerUserId = u.Id
LEFT JOIN 
    Comments c ON c.UserId = u.Id
LEFT JOIN 
    Votes v ON v.UserId = u.Id
LEFT JOIN 
    Badges b ON b.UserId = u.Id
LEFT JOIN 
    Posts pl ON pl.OwnerUserId = u.Id
LEFT JOIN 
    PostLinks pl2 ON pl2.PostId = p.Id
LEFT JOIN 
    Votes v2 ON v2.PostId = pl.Id AND v2.UserId = u.Id
LEFT JOIN 
    Votes v3 ON v3.PostId = p.Id AND v3.UserId = u.Id
LEFT JOIN
    Votes VotesReceived ON VotesReceived.PostId = p.Id
WHERE 
    u.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
GROUP BY 
    u.Id,
    u.DisplayName
ORDER BY 
    TotalPosts DESC
LIMIT 100;