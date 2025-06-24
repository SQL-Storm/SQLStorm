
SELECT TOP 10 p.Title, p.CreationDate, u.DisplayName
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1 
ORDER BY p.CreationDate DESC;
