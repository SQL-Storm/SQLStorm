
SELECT TOP 10 p.Id, p.Title, p.Score, p.ViewCount, u.DisplayName
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1 
ORDER BY p.Score DESC;
