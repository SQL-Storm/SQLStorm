-- {"query": "6334.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 413} 

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
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId END) AS UpvoteCount,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId END) AS DownvoteCount,
    MAX(CASE WHEN ph.PostHistoryTypeId = 1 THEN ph.CreationDate END) AS FirstEditedDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN cl.Name END) AS LastCloseReason,
    AVG(p.ViewCount) AS AvgViewCount,
    MAX(p.LastActivityDate) AS LastActivePostDate
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
LEFT JOIN 
    CloseReasonTypes cl ON ph.Comment = CAST(cl.Id AS varchar)
WHERE 
    u.Reputation > 1000 
    AND u.LastAccessDate > DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 30 DAY)
    AND p.PostTypeId IN (1, 2)
GROUP BY 
    u.Id
HAVING 
    AVG(p.ViewCount) > 100
ORDER BY 
    TotalScore DESC, 
    PostCount DESC
LIMIT 100;
