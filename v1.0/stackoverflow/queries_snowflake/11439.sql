
SELECT 
    p.Id AS PostId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    p.ViewCount,
    p.Score,
    u.Id AS UserId,
    u.DisplayName AS UserDisplayName,
    u.Reputation,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
    (SELECT LISTAGG(b.Name, ', ') WITHIN GROUP (ORDER BY b.Name) FROM Badges b WHERE b.UserId = u.Id) AS Badges
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    p.PostTypeId = 1 
GROUP BY 
    p.Id, 
    p.Title, 
    p.CreationDate, 
    p.ViewCount, 
    p.Score, 
    u.Id, 
    u.DisplayName, 
    u.Reputation
ORDER BY 
    p.CreationDate DESC
LIMIT 100;
