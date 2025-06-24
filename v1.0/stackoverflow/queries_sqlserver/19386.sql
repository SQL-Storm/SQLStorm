
SELECT TOP 10 p.Title, p.CreationDate, u.DisplayName, v.VoteTypeId
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON p.Id = v.PostId
WHERE p.PostTypeId = 1  
ORDER BY p.CreationDate DESC;
