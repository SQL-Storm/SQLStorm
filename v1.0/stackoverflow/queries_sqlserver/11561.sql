
SELECT 
    p.Title AS PostTitle,
    p.CreationDate AS PostCreationDate,
    u.DisplayName AS OwnerDisplayName,
    COALESCE(v.VoteCount, 0) AS TotalVotes,
    COALESCE(c.CommentCount, 0) AS TotalComments,
    COALESCE(ph.EditedCount, 0) AS TotalEdits,
    COALESCE(b.BadgeCount, 0) AS TotalBadges
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    (SELECT PostId, COUNT(*) AS VoteCount
     FROM Votes
     GROUP BY PostId) v ON p.Id = v.PostId
LEFT JOIN 
    (SELECT PostId, COUNT(*) AS CommentCount
     FROM Comments
     GROUP BY PostId) c ON p.Id = c.PostId
LEFT JOIN 
    (SELECT PostId, COUNT(*) AS EditedCount
     FROM PostHistory
     WHERE PostHistoryTypeId IN (4, 5, 6) 
     GROUP BY PostId) ph ON p.Id = ph.PostId
LEFT JOIN 
    (SELECT U.Id, COUNT(b.Id) AS BadgeCount
     FROM Badges b
     JOIN Users U ON b.UserId = U.Id
     GROUP BY U.Id) b ON u.Id = b.Id
WHERE 
    p.PostTypeId = 1 
GROUP BY 
    p.Title, p.CreationDate, u.DisplayName, v.VoteCount, c.CommentCount, ph.EditedCount, b.BadgeCount
ORDER BY 
    p.CreationDate DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
