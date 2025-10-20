SELECT 
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.CreationDate AS PostCreationDate,
    u.DisplayName AS PostOwner,
    u.Reputation AS PostOwnerReputation,
    p.ViewCount,
    p.Score AS PostScore,
    COUNT(DISTINCT c.Id) AS CommentCount,
    AVG(c.Score) AS AvgCommentScore,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    MAX(b.Date) AS LastBadgeDate,
    STRING_AGG(t.TagName, ', ' ORDER BY t.TagName) AS Tags
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Badges b ON p.OwnerUserId = b.UserId
LEFT JOIN 
    Tags t ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%' 
WHERE 
    p.PostTypeId = 1 -- Filter for Questions
    AND p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
GROUP BY 
    p.Id, p.Title, p.CreationDate, u.DisplayName, u.Reputation, p.ViewCount, p.Score
ORDER BY 
    p.ViewCount DESC, TotalVotes DESC, AvgCommentScore DESC
LIMIT 50;