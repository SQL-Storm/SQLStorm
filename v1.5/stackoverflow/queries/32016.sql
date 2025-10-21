SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    u.Reputation, 
    p.Id AS PostId, 
    p.Title AS PostTitle, 
    p.Score AS PostScore, 
    COUNT(DISTINCT c.Id) AS CommentCount, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes, 
    COUNT(DISTINCT pb.Id) AS BadgeCount, 
    t.TagName AS DistinctTag
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Badges pb ON u.Id = pb.UserId
LEFT JOIN 
    (
        SELECT 
            ph.UserId, ph.PostId, unnest(string_to_array(substring(ph.Text, 2, length(ph.Text) - 2), '><')) AS TagName
        FROM 
            PostHistory ph
        WHERE 
            ph.PostHistoryTypeId = 6
    ) t ON t.PostId = p.Id
LEFT JOIN 
    Tags dt ON dt.TagName = t.TagName
WHERE 
    u.Reputation > 10000
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, p.Id, p.Title, p.Score, t.TagName
ORDER BY 
    u.Reputation DESC, BadgeCount DESC, UpVotes DESC;