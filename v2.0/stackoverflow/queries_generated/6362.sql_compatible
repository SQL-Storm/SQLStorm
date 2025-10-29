SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(p.Score) AS TotalScore,
    MAX(p.LastActivityDate) AS LastActivePost,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 1 THEN v.PostId END) AS AcceptedAnswerCount,
    AVG(p.ViewCount) AS AvgViewCount,
    MAX(ph.CreationDate) AS LastEdited,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReason,
    MAX(CASE WHEN ph.PostHistoryTypeId = 33 THEN ph.Comment END) AS PostNotice
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 1
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    p.PostTypeId = 1 
    AND u.Reputation > 1000 
    AND p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1' YEAR)
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes
HAVING 
    AVG(p.Score) > 100 
    AND COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalScore DESC, 
    PostCount DESC
LIMIT 100;