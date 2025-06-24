
SELECT TOP 10 p.Id, p.Title, p.CreationDate, p.ViewCount, u.DisplayName AS Owner
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1
ORDER BY p.CreationDate DESC;
